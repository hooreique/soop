# SOOP for NixOS

SOOP의 Windows용 시청자 그리드 에이전트와 Chromium 웹 앱을 함께 실행하는
로컬 Nix flake다. 기본 앱은 먼저 공식 `SOOPPackage.exe`를 준비해 브라우저
감지용 WebSocket을 `21201` 포트에 열고, 전용 Chromium 프로필로
`sooplive.com`을 표시한다. 재생 세션이 생기면 `SOOPPackage.exe`가
`SOOPStreamer.exe` P2P 작업자를 실행한다.

## 사용법

```console
$ nix run .                 # 통합 SOOP 앱
$ nix run .#soop            # 위와 동일
$ nix run .#soop-grid       # 그리드 에이전트만 foreground로 실행
$ nix run .#soop-grid -- --status
$ nix run .#soop-grid -- --stop
$ nix build .
$ nix build .#soop-grid
```

`nix profile install .`은 `soop` 실행 파일과 `SOOP` 데스크톱 항목을 설치한다.
그리드만 따로 사용하려면 `nix profile install .#soop-grid`를 실행한다. 이 경우
`soop-grid` 실행 파일과 `SOOP Grid` 데스크톱 항목이 추가된다.

flake는 비자유 SOOP 바이너리를 사용하므로 내부 nixpkgs import에
`allowUnfree = true`를 명시한다. 다른 flake에서 패키지를 직접 다시 구성하면
그 nixpkgs 인스턴스에도 비자유 패키지 허용 설정이 필요하다.

## 수명주기

통합 앱은 단일 인스턴스다. `soop`이 실행 중일 때 다시 실행해도 새 창이나 새
그리드를 만들지 않는다.

```text
soop 실행
  -> 전용 Wine prefix에서 그리드 실행
  -> 21201 준비 확인
  -> Chromium 앱 창 실행
  -> Chromium 창 종료
  -> SOOPPackage, SOOPStreamer, wineserver 종료
  -> 21201 포트 닫힘
```

Chromium에는 background mode를 끄는 옵션을 적용한다. wrapper는 Chromium과
그리드를 자식 프로세스로 감시하며, 창을 닫거나 wrapper가 종료되면 전용
`wineserver`가 끝날 때까지 기다린다. Linux 자동 시작 항목이나 systemd
서비스는 만들지 않으므로 앱이 닫힌 뒤 상시 SOOP 데몬은 남지 않는다.

`soop-grid`도 foreground supervisor로 동작한다. 터미널의 `Ctrl-C`, 데스크톱
세션 종료 또는 벤더 트레이의 종료 동작으로 wrapper가 끝나면 해당 Wine
프로세스를 모두 정리한다. 통합 앱과 그리드 전용 앱은 동시에 실행할 수 없다.

## 저장 위치

런타임 프로세스는 모두 종료하지만 로그인과 설치를 매번 반복하지 않도록 다음
파일은 디스크에 유지한다.

- Chromium 프로필과 로그인 쿠키: `$XDG_DATA_HOME/soop/chromium/`
- Wine prefix와 자동 갱신 파일: `$XDG_DATA_HOME/soop/grid/`
- Chromium 캐시: `$XDG_CACHE_HOME/soop/chromium/`
- 그리드 로그: `$XDG_STATE_HOME/soop/grid/agent.log`
- 단일 인스턴스 lock: `$XDG_RUNTIME_DIR/soop/`

XDG 변수가 없으면 `~/.local/share`, `~/.cache`, `~/.local/state` 아래를
사용한다. 공식 안정 채널 실행 파일과 최소 VC71 런타임은 빌드 시 원본 URL에서
받아 Nix store에 고정한 뒤, 최초 실행 때 쓰기 가능한 그리드 데이터 디렉터리로
복사한다. Nix store 내부에는 런타임 데이터를 쓰지 않는다.

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
- 최초 실행은 Wine prefix와 Chromium 프로필 초기화 때문에 시간이 걸릴 수 있다.
- 시청 그리드는 P2P이므로 방송 재생 중 업로드 대역폭을 사용한다.
- `21201`은 고정 bootstrap 포트지만 실제 시청 작업자의 포트는 동적이다.
- SOOP의 단계적 업데이트는 XDG 데이터 디렉터리의 쓰기 가능한 복사본에
  적용된다.
- Chromium의 로컬 네트워크 접근 정책이 localhost 연결을 차단하면 SOOP에
  로컬 네트워크 권한을 허용해야 한다.
- 실제 방송의 1080p 재생 여부는 방송 상태, 지역 정책, 최신 플레이어와 벤더
  서비스 응답에 영향을 받으므로 빌드 과정에서 자동 시험하지 않는다.
