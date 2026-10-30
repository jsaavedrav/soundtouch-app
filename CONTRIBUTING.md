# Contribuir

¡Gracias por querer ayudar! *Contributions in English are welcome too.*

## Antes de empezar

- Para algo más grande que un arreglo chico, abre primero un issue para
  conversarlo.
- Si reportas un problema, indica el modelo del parlante y su firmware. Los
  obtienes con `swift run soundtouch <ip> status` o en
  `http://<ip>:8090/info`.

## Estructura

- `Sources/SoundTouchKit`: cliente de la API local, sin dependencias. Todo lo
  que hable con los parlantes va aquí, con tests.
- `Sources/soundtouch`: herramienta de terminal para probar contra parlantes
  reales.
- `App`: la app SwiftUI para iPhone y Mac. El proyecto de Xcode se genera con
  XcodeGen desde `App/project.yml` y no se versiona.

## Flujo

1. Haz un fork y una rama desde `main`.
2. Corre `swift test` y, si tocas la app, compílala para iOS y macOS.
3. Abre un PR que diga qué cambia y con qué parlantes lo probaste.

## Datos de prueba

Las respuestas de `/sources` y `/info` incluyen correos de cuentas de Spotify,
números de serie y direcciones MAC. Antes de agregarlas como fixtures,
reemplázalas por valores inventados.
