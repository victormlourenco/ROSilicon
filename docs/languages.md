# Languages

The window, the log and the error messages are translated into **English**,
**Portuguese (Brazil)** and **Spanish**; macOS picks the one matching the
reader's language and falls back to English for anything a translation is
missing. Every Portuguese variant resolves to `pt-BR` and every Spanish one to
`es`, so a reader set to `pt-PT` or `es-MX` still gets their own language.

Each string lives once in [Strings.swift](../Sources/ROSilicon/Strings.swift)
and once per language in `Resources/Localizations/<lang>.lproj/Localizable.strings`.
To add a language, copy `en.lproj` to, say, `fr.lproj`, translate the values, and
build — `build.sh` picks up every `.lproj` it finds and lists them in the bundle.

