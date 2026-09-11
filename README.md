# SOOP for NixOS

SOOP에서 FHD 이상의 해상도로 시청하려면 Windows와 macOS용으로 제공되는
독점 그리드 에이전트가 필요하다. 이 NixOS용 Chromium 앱은 Windows용
에이전트를 활용해 Linux에서도 고화질로 시청할 수 있게 한다.
앱 창을 닫으면 함께 실행한 그리드도 종료한다.

> [!IMPORTANT]
> 이 프로젝트는 개인적으로 제작했으며, SOOP의 인가를 받지 않았다.

## 설치 및 실행

`x86_64-linux`와 flakes를 사용할 수 있는 Nix 환경이 필요하다.
저장소 디렉터리에서 실행한다.

```console
$ nix run .
```

설치해서 사용하려면:

```console
$ nix profile install .
```

설치 후 앱 메뉴의 **SOOP** 또는 터미널의 `soop`으로 실행한다.

### 다른 flake에서 overlay 사용하기

이 저장소를 `inputs.soop`으로 추가한 flake에서는 기본 overlay를 적용해
소비자의 nixpkgs에 `pkgs.soop`과 `pkgs.soop-grid`를 추가할 수 있다.
지원 플랫폼은 `x86_64-linux`이며, 비자유 패키지 허용은 소비자 쪽에서 설정한다.

```nix
pkgs = import inputs.nixpkgs {
  inherit system;
  config.allowUnfree = true;
  overlays = [
    inputs.soop.overlays.default
  ];
};
```

overlay가 적용된 `pkgs`를 사용하는 NixOS 설정에서는
`environment.systemPackages = [ pkgs.soop ];`으로 통합 앱을 설치한다.
그리드만 설치하려면 `pkgs.soop-grid`를 사용한다. Home Manager에서는
같은 패키지를 `home.packages`에 추가한다.

## 사용 시 참고

- 최초 실행은 초기화 때문에 시간이 걸릴 수 있다. 로그인 정보는 다음 실행에도 유지된다.
- 방송 재생 중 P2P 그리드가 업로드 대역폭을 사용한다.
- 앱은 한 번에 하나만 실행할 수 있다.

## 그리드만 사용하기

```console
$ nix run .#soop-grid
$ nix run .#soop-grid -- --status
$ nix run .#soop-grid -- --stop
```

터미널에서 `Ctrl-C`로도 종료할 수 있다. 설치하려면
`nix profile install .#soop-grid`를 실행한다. 설치 후 `soop-grid` 명령이나
앱 메뉴의 **SOOP Grid**로 실행한다. 통합 앱과 동시에 실행할 수 없다.

개발·유지보수, 데이터·로그 위치, 구현 및 설계 결정은
[CONTRIBUTING](CONTRIBUTING.md)을 참고한다.
