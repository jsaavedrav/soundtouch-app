# soundtouch-app

App de código abierto para seguir usando los parlantes Bose SoundTouch después
de que Bose descontinuara su aplicación. Habla directo con la API local de cada
parlante (puerto 8090), sin pasar por la nube de Bose.

*Open-source iPhone and Mac app to keep using Bose SoundTouch speakers after
Bose discontinued its app. It talks to each speaker's local web API only.*

## Estado

- [x] `SoundTouchKit`: paquete Swift con descubrimiento Bonjour y los comandos
      del MVP (encender y apagar, volumen, cambio de fuente AUX / Bluetooth).
- [ ] App SwiftUI para iPhone y Mac.
- [ ] Radio por internet, Spotify, presets y multiroom.

Probado con un SoundTouch 10 y un SoundTouch 20 (primera versión, sin
Bluetooth), firmware 27.0.6.

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

## Licencia

MIT. Este proyecto no está afiliado a Bose. "Bose" y "SoundTouch" son marcas de
Bose Corporation.
