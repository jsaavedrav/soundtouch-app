# soundtouch-app

App de código abierto para seguir usando los parlantes Bose SoundTouch después
de que Bose descontinuara su aplicación. Habla directo con la API local de cada
parlante (puerto 8090), sin pasar por la nube de Bose.

*Open-source iPhone and Mac app to keep using Bose SoundTouch speakers after
Bose discontinued its app. It talks to each speaker's local web API only.*

## Estado

- [x] `SoundTouchKit`: paquete Swift con descubrimiento Bonjour y los comandos
      del MVP (encender y apagar, volumen, cambio de fuente AUX / Bluetooth).
- [x] App SwiftUI para iPhone y Mac: encuentra los parlantes y controla
      encendido, volumen y fuente, al día con los botones físicos.
- [ ] Radio por internet, Spotify, presets y multiroom (ver los
      [issues](https://github.com/jsaavedrav/soundtouch-app/issues)).

Probado con un SoundTouch 10 y un SoundTouch 20 (primera versión, sin
Bluetooth), firmware 27.0.6.

## Descargar para Mac

Descarga `SoundTouch-…-macOS.zip` de la [última versión](https://github.com/jsaavedrav/soundtouch-app/releases/latest),
descomprímelo y mueve **SoundTouch** a Aplicaciones. Funciona en Mac con Apple
Silicon e Intel, con macOS 14 o superior.

La app no está firmada con una cuenta de Apple Developer, así que la primera vez
macOS la bloquea. Para abrirla, intenta abrirla una vez y luego ve a
*Ajustes del Sistema* → *Privacidad y seguridad* → **Abrir igualmente**. También
puedes quitar la marca de descarga desde la terminal:

```sh
xattr -dr com.apple.quarantine /Applications/SoundTouch.app
```

Para el iPhone por ahora hay que compilarla con Xcode (ver abajo).

## Compilar la app para tu iPhone o Mac

Requiere Xcode 16 o superior y [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd App && xcodegen && open SoundTouch.xcodeproj
```

En Xcode, abre el target *SoundTouch* → *Signing & Capabilities* y elige tu
equipo (sirve una cuenta de Apple gratuita). Luego elige tu iPhone o *My Mac*
como destino y pulsa ▶. La primera vez, iOS pide permiso para usar la red
local: acéptalo, porque sin él no puede encontrar los parlantes.

Si la búsqueda no encuentra un parlante, puedes agregarlo por su IP con el
botón **+**.

## Probar desde la terminal (macOS)

Requiere Xcode 15 o superior.

```sh
swift run soundtouch discover               # lista los parlantes de la red
swift run soundtouch 192.168.1.20 status
swift run soundtouch 192.168.1.20 on        # u off
swift run soundtouch 192.168.1.20 volume 25 # o up / down
swift run soundtouch 192.168.1.20 sources   # entradas físicas disponibles
swift run soundtouch 192.168.1.20 source AUX
```

## Usar `SoundTouchKit`

```swift
import SoundTouchKit

let speakers = await SoundTouchDiscovery.discover()
let client = speakers[0].client()

try await client.powerOn()
try await client.setVolume(30)
if let aux = try await client.sources().first(where: { $0.source == "AUX" }) {
    try await client.select(aux)
}
```

En iOS la app debe declarar `NSLocalNetworkUsageDescription` y
`NSBonjourServices` = `_soundtouch._tcp` en su Info.plist.

## Tests

```sh
swift test
```

## Contribuir

Las ideas, reportes y PR son bienvenidos. Revisa [CONTRIBUTING.md](CONTRIBUTING.md)
y los [issues abiertos](https://github.com/jsaavedrav/soundtouch-app/issues).

## Publicar una versión

Crea un tag `v` + versión y súbelo. El workflow *Release* compila la app para
Mac y la publica en GitHub Releases:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

## Licencia

MIT. Este proyecto no está afiliado a Bose. "Bose" y "SoundTouch" son marcas de
Bose Corporation.
