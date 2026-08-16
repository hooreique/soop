# SOOP Grid for NixOS

SOOP의 Windows용 시청자 그리드 에이전트를 전용 Wine 환경에서 실행하는
로컬 Nix flake다. 웹사이트를 Chromium 앱 모드로 감싸는 대신 공식
`SOOPPackage.exe`를 실행한다. 이 프로세스가 브라우저 감지용 WebSocket을
`21201` 포트에 열고, 재생 세션이 생기면 `SOOPStreamer.exe` 작업자를 실행한다.

## 사용법

```console
$ nix run .
$ nix run . -- --open       # 에이전트 실행 후 기본 브라우저 열기
$ nix run . -- --status
$ nix build .
$ nix profile install .
```

설치 후 실행 파일은 `soop-grid`, GNOME 앱 목록의 이름은 `SOOP Grid`다.
데스크톱 항목은 에이전트를 시작한 뒤 기본 브라우저로 SOOP을 연다.

flake는 비자유 SOOP 바이너리를 사용하므로 내부 nixpkgs import에
`allowUnfree = true`를 명시한다. 다른 flake에서 패키지를 직접 다시 구성하면
그 nixpkgs 인스턴스에도 비자유 패키지 허용 설정이 필요하다.

## 저장 위치

공식 안정 채널의 실행 파일과 최소 VC71 런타임은 빌드 시 원본 URL에서 받아
Nix store에 고정한다. 실행 시 다음 쓰기 가능한 위치로 한 번 복사한다.

- Wine prefix와 자동 갱신 파일: `$XDG_DATA_HOME/soop-grid/`
- 로그: `$XDG_STATE_HOME/soop-grid/agent.log`
- XDG 변수가 없을 때: `~/.local/share`와 `~/.local/state`

같은 seed 버전에서는 복사를 반복하지 않으므로 벤더 자동 갱신 결과도 유지된다.
flake의 고정 버전을 갱신하면 새 seed를 다시 배치한다. Nix store의 파일을 직접
실행하거나 그 안에 쓰지 않는다.

## 현재 배포물

2026-08-16에 확인한 공식 설치 프로그램은 다음과 같다.

- URL: `https://creatorup.sooplive.com/SOOPStreamer_installer.exe`
- 설치 프로그램 버전: `1.0.0.1`
- SHA-256: `sha256-olSn2T+CcdWvW8LPMDeLy6BA/95pzzsrtXVKOwxUQgg=`
- 무인 설치 인자: `/S` (대소문자 구분)

이 설치 프로그램은 현재 파일을 다시 내려받는 부트스트랩이므로 flake에서는
사용하지 않는다. 대신
`https://creatorup.sooplive.com/SOOP/SOOPFileList.xml`의 안정 채널 파일을
직접 고정한다. 현재 `SOOPStreamer.exe` 버전은 `26.7.14.1201`이다.

버전을 갱신하려면 XML의 파일 목록을 확인하고 `package.nix`의 버전과 해시를
바꾼다. XML의 `H`는 압축 해제된 파일의 해시이므로 Nix 소스 해시로 바로 쓸 수
없다. 각 `.gz` URL에 다음 명령을 실행해 출력되는 SRI 해시를 사용한다.

```console
$ nix store prefetch-file --json \
    https://creatorup.sooplive.com/SOOP/SOOPPackage.exe.gz
```

## 알려진 제한 사항

- `x86_64-linux`만 제공한다.
- 최초 실행은 Wine prefix 초기화 때문에 시간이 걸릴 수 있다.
- 시청 그리드는 P2P이므로 방송 재생 중 업로드 대역폭을 사용한다.
- `21201`은 고정 bootstrap 포트지만 실제 시청 작업자의 포트는 동적이다.
- SOOP의 단계적 업데이트가 고정 seed보다 먼저 배포될 수 있으며, 이 업데이트는
  XDG 데이터 디렉터리의 쓰기 가능한 복사본에 적용된다.
- Chromium의 로컬 네트워크 접근 정책이 localhost 연결을 차단하면 사이트별
  로컬 네트워크 권한을 허용해야 할 수 있다.
- 빌드 검증만으로 실제 방송의 1080p 재생까지 자동 시험할 수는 없다. 방송 상태,
  지역 정책, 최신 플레이어와 벤더 서비스의 응답에 영향을 받는다.
