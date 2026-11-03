# Third-Party Notices

Ombre is licensed under the GNU General Public License v3.0 (see `LICENSE`).

Ombre is derived from [Ora Browser](https://github.com/the-ora/browser) (the-ora/browser), licensed under GPL-3.0.

Ombre includes the third-party components below, which remain subject to their own licenses. The same list is shown
in the app (Ombre menu › Licenses).

## Swift packages

| Component | Version | License | Source |
| --- | --- | --- | --- |
| SafariConverterLib (AdGuard) | 4.2.2 | GPL-3.0 | https://github.com/AdguardTeam/SafariConverterLib |
| Sparkle | 2.10.0 | MIT, with BSD-licensed parts (see its LICENSE) | https://github.com/sparkle-project/Sparkle |
| FavIconFinder | 5.1.5 | MIT | https://github.com/will-lumley/FavIconFinder |
| SwiftSoup (via FavIconFinder) | 2.14.3 | MIT | https://github.com/scinfu/SwiftSoup |
| PunycodeSwift (via SafariConverterLib) | 3.0.0 | MIT | https://github.com/gumob/PunycodeSwift |
| swift-psl | 1.1.188 | MIT | https://github.com/ameshkov/swift-psl |
| Public Suffix List data (in swift-psl) | — | MPL-2.0 | https://publicsuffix.org |
| Swift Argument Parser (via SafariConverterLib) | 1.5.0 | Apache-2.0 | https://github.com/apple/swift-argument-parser |
| Inject | 1.6.0 | MIT | https://github.com/krzysztofzablocki/Inject |

Exact versions are pinned in `Ombre.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Vendored source

### SplitView

- Upstream project: [stevengharris/SplitView](https://github.com/stevengharris/SplitView)
- Upstream source path: `Sources/SplitView`
- Local path: `Ombre/Shared/Layout/SplitView`
- License: MIT
- Included license text: `Vendor/SplitView/LICENSE`

The files in `Ombre/Shared/Layout/SplitView` were copied from the upstream `SplitView` project and may include local
modifications.

## Data downloaded at runtime

Content-blocking filter lists (AdGuard and others) are downloaded from their authors when protections are turned on
and keep their own licenses.
