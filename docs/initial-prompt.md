# Task: NixOS용 SOOP 그리드 클라이언트 래퍼 만들기

## 목표

NixOS에서 SOOP(`sooplive.com`) 방송의 1080p 화질을 사용할 수 있도록, SOOP이 제공하는 Windows용 시청자 그리드 에이전트를 Wine과 함께 실행하는 간단한 Nix flake를 구현한다.

단순히 Chrome을 SOOP 웹사이트의 앱 모드로 여는 `netflix`식 래퍼가 아니라, `spotify/linux.nix`처럼 **벤더 배포물을 가져와 풀고, 필요한 런타임과 함께 실제 프로그램을 깔끔하게 래핑하며, 실행 파일·데스크톱 항목·아이콘을 제공하는 방식**을 우선 참고한다.

참고 파일:

- <https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/by-name/sp/spotify/linux.nix>
- <https://github.com/TheSiahxyz/.dotfiles/blob/master/ar/.local/bin/iwaf>
- <https://github.com/famomatic/ytv1/blob/main/docs/SOOP_P2P_GRID_ANALYSIS.md>

## 구현 방향

- `flake.nix` 하나만으로 바로 시험할 수 있게 구성한다. 필요하다면 내부적으로 `package.nix`를 분리해도 된다.
- 최소한 `packages.x86_64-linux.default`와 `apps.x86_64-linux.default`를 제공한다.
- 공식 SOOP 설치 파일의 현재 다운로드 URL과 설치 결과물을 조사한다.
- 방송 송출 프로그램이 아니라 **시청용 그리드 에이전트**가 무엇인지 확인한다. 특히 `SOOPPackage.exe`와 `SOOPStreamer.exe`의 역할을 구분해서 올바른 프로세스를 실행해야 한다.
- 가능하면 설치 파일을 빌드 시점에 가져와 압축 해제하고, 실행에 필요한 불변 파일은 Nix store에 둔다.
- Wine prefix, 로그, 캐시, 자동 갱신 데이터처럼 쓰기가 필요한 상태는 Nix store 밖의 XDG 데이터 디렉터리에 둔다.
- 빌드 시 추출이 현실적으로 어렵다면 최초 실행 시 전용 Wine prefix에 무인 설치하는 방식도 허용한다. 이 경우에도 이후 실행은 멱등적이어야 하며 매번 재설치하지 않아야 한다.
- Wine 및 필요한 Windows 런타임 의존성은 wrapper가 준비한다. 필요한 구성 요소는 실제 실행 결과를 보고 최소한으로 결정한다.
- 사용자가 별도로 Wine 설정을 하지 않아도 실행되도록 전용 `WINEPREFIX`를 사용한다.
- 에이전트가 이미 실행 중이면 중복 실행하지 않는다.
- 에이전트 실행 후 SOOP 사이트를 기본 Linux 브라우저로 여는 동작은 선택적으로 제공해도 된다. 핵심은 웹사이트 래핑이 아니라 그리드 에이전트 실행이다.
- 가능하면 `.desktop` 파일과 적절한 아이콘도 설치하여 GNOME 앱 목록에서 실행할 수 있게 한다.
- Wayland 환경을 깨뜨리는 불필요한 X11 강제 설정은 하지 않는다. 단, Wine 자체에 필요한 설정은 허용한다.
- nixpkgs 제출 품질까지 맞출 필요는 없지만, 구조와 이름은 읽기 쉽고 이후 유지보수하기 편하게 작성한다.

## 기대 산출물

- `flake.nix`
- 필요할 경우 `package.nix` 또는 보조 실행 스크립트
- `nix run .`으로 실행 가능한 기본 앱
- `nix build .`로 빌드 가능한 기본 패키지
- 짧은 사용법과 알려진 제한 사항
- 버전과 다운로드 해시를 갱신하는 방법에 대한 짧은 주석 또는 스크립트

## 완료 조건

다음이 실제 NixOS 환경에서 확인되어야 한다.

1. `nix run .`으로 전용 Wine 환경과 SOOP 시청용 그리드 에이전트가 실행된다.
2. 두 번째 실행부터는 설치 과정을 반복하지 않는다.
3. 에이전트의 로컬 서비스가 정상적으로 열리고 SOOP 웹 플레이어가 이를 감지한다. 현재 알려진 제어 포트는 `21201`이지만, 구현 전에 최신 클라이언트에서 다시 확인한다.
4. SOOP 방송에서 그리드 사용이 필요한 1080p 또는 원본 화질을 선택해 재생할 수 있다.
5. 패키지가 Nix store 내부에 런타임 데이터를 쓰려고 하지 않는다.
6. `nix profile install .` 또는 NixOS 설정의 `environment.systemPackages`에 넣었을 때 실행 파일과 데스크톱 항목이 정상적으로 노출된다.

## 유의사항

- SOOP 배포물은 비자유 소프트웨어일 가능성이 높으므로 라이선스와 `allowUnfree` 처리를 명시한다.
- 공식 바이너리를 재배포하지 말고 원본 URL에서 가져오는 방식으로 구성한다.
- 사용자 로그인 정보나 브라우저 쿠키를 패키지에 포함하지 않는다.
- SOOP 클라이언트 업데이트로 파일명, 포트, 설치 위치가 바뀔 수 있으므로 해당 값은 한곳에 모아 관리한다.
- 우선 목표는 완벽한 범용 패키지가 아니라, 현재 NixOS x86_64-linux에서 재현 가능하게 동작하는 작은 로컬 flake다.
