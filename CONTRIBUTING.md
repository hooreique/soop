# 개발 및 유지보수

사용 방법은 [README](README.md)를 참고한다. 이 문서는 패키징 구조, 런타임
동작과 설계 결정, 배포물 갱신 방법을 정리한다.

## 빌드 및 확인

저장소 디렉터리에서 실행한다.

```console
$ nix build .
$ nix build .#soop-grid
```

두 패키지는 빌드 시 Bash 구문 검사와 ShellCheck를 실행한다. 런타임 변경 시에는
`nix run .`으로 실행하고, 창을 닫은 뒤 그리드 프로세스가 종료되는지 확인한다.
그리드 상태는 `nix run .#soop-grid -- --status`로 확인할 수 있다.

실제 방송의 1080p 재생 여부는 방송 상태, 지역 정책, 최신 플레이어와 벤더
서비스 응답에 영향을 받으므로 빌드 과정에서 자동 시험하지 않는다.

flake는 비자유 SOOP 바이너리를 사용하므로 내부 nixpkgs import에
`allowUnfree = true`를 명시한다. 다른 flake에서 패키지를 직접 다시 구성하면
그 nixpkgs 인스턴스에도 비자유 패키지 허용 설정이 필요하다.

## 패키징과 원본 스크립트

`package.nix`는 그리드의 바이너리·런타임·아이콘을, `webapp.nix`는 Chromium
앱과 확장을 패키징한다. 두 패키지는 Bash 원본을 설치하고 Nix의 shebang 교정,
`makeShellWrapper`의 런타임 `PATH`·상수 주입, `makeDesktopItem`과
`copyDesktopItems`의 데스크톱 항목 생성을 사용한다. 빌드 시 원본에
`bash -n`과 ShellCheck 검사를 실행한다.

원본을 `bash soop.sh` 또는 `bash soop-grid.sh`로 직접 실행하려면 런타임
명령을 `PATH`에 제공하고 다음 환경변수를 설정해야 한다.

| 원본 | 필수 환경변수 |
|---|---|
| `soop.sh` | `SOOP_GRID_BIN`: 그리드 실행 파일의 절대 경로, `SOOP_CHROMIUM_BIN`: Chromium 실행 파일의 절대 경로, `SOOP_EXTENSION_DIR`: 확장 디렉터리 |
| `soop-grid.sh` | `SOOP_GRID_PAYLOAD_DIR`: 그리드 배포 파일 디렉터리, `SOOP_GRID_RUNTIME_DIR`: VC71 DLL 디렉터리, `SOOP_GRID_SEED_VERSION`: `패키지버전-스트리머버전` |

필요한 런타임 도구는 통합 앱의 경우 coreutils·util-linux·jq, 그리드는
coreutils·util-linux·iproute2·Xvfb·Wine이다. 필수 환경변수가 없거나 비어 있으면
상태 파일 생성이나 프로세스 실행 전에 오류로 종료한다. `--help`는 이 변수
없이도 사용할 수 있다. 패키지 wrapper는 이 값을 고정하며 외부 환경변수를
덮어쓰므로 사용자 설정용 옵션이 아니다.

## 그리드 구성과 수명주기

기본 앱은 먼저 공식 `SOOPPackage.exe`를 준비해 브라우저 감지용 WebSocket을
`21201` 포트에 열고, 전용 Chromium 프로필로 `sooplive.com`을 표시한다.
재생 세션이 생기면 `SOOPPackage.exe`가 `SOOPStreamer.exe` P2P 작업자를
실행한다. `21201`은 고정 bootstrap 포트지만 실제 시청 작업자의 포트는 동적이다.

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

wrapper는 Chromium을 시작하기 전에 `www.sooplive.com`과
`play.sooplive.com`의 localhost 접근 권한을 전용 프로필에 허용한다. 따라서
SOOP 그리드 감지에 필요한 브라우저 권한 팝업을 별도로 처리하지 않아도 된다.

통합 앱은 로컬 Chromium 확장을 함께 로드한다. SOOP 페이지에서 일반 클릭이나
`window.open()`이 새 창을 요청하면 현재 앱 창에서 이동하며, 사용자가 보조 키와
함께 클릭한 경우와 다운로드, URL 없는 팝업은 원래 동작을 유지한다. 극장 모드처럼
페이지가 `Ctrl+W`를 가로채는 상황에서도 Chromium의 창 닫기 동작을 유지한다.

`soop-grid`도 foreground supervisor로 동작한다. 터미널의 `Ctrl-C`, 데스크톱
세션 종료 또는 `soop-grid --stop`으로 wrapper가 끝나면 해당 Wine 프로세스를
모두 정리한다. Wine은 전용 가상 디스플레이에서 실행되므로 스트리머의 내부
창이나 트레이 아이콘은 데스크톱에 표시되지 않는다. 통합 앱과 그리드 전용 앱은
동시에 실행할 수 없다.

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

SOOP의 단계적 업데이트는 XDG 데이터 디렉터리의 쓰기 가능한 복사본에 적용된다.

## 배포물과 버전 갱신

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
