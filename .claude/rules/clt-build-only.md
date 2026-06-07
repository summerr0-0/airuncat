# CLT Build Only

이 머신엔 Command Line Tools만 있고 풀 Xcode가 없다.

- 빌드는 `swift build` 또는 `./build.sh` 만 사용한다.
- `xcodebuild`, `.xcodeproj`, `.xcworkspace`, 에셋 카탈로그(`.xcassets`)에 의존하지 마라.
- `.app` 번들은 `build.sh`가 수동 조립한다: 바이너리 복사 + `Info.plist` 복사 + ad-hoc `codesign`.
- 풀 Xcode는 SwiftUI 프리뷰 캔버스나 배포(notarization)가 필요해질 때만 도입을 검토한다.
