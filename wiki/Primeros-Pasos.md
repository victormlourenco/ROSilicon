# Primeros Pasos

[🇺🇸 English](Getting-Started) · [🇧🇷 Português](Primeiros-Passos) · 🇪🇸 Español

ROSilicon instala Ragnarok Online LATAM en tu Mac y lo ejecuta. No necesitas
Windows, ni Boot Camp, ni saber nada de Wine — la app ya lleva todo dentro
menos el cliente del juego, que descarga por ti.

<p align="center">
  <img src="https://raw.githubusercontent.com/wiki/victormlourenco/ROSilicon/images/launcher-es.png" width="620" alt="La ventana de ROSilicon, lista para jugar">
</p>

## Antes de empezar

- Un Mac con **Apple Silicon** — M1, M2, M3, M4 o más reciente. Los Mac con
  Intel no son compatibles. (Menú Apple › **Acerca de este Mac**: la línea del
  chip debe decir *Apple*.)
- **macOS 14 Sonoma** o más reciente.
- **Rosetta 2.** Si nunca lo has instalado, abre el Terminal y ejecuta
  `softwareupdate --install-rosetta`. La app también lo comprueba y te avisa en
  un segundo si falta.
- Unos **12 GB libres** en el disco. Solo el cliente del juego son unos 4,8 GB
  de descarga.

## 1. Descarga

Entra en la [página de versiones](https://github.com/victormlourenco/ROSilicon/releases/latest)
y descarga **ROSilicon-&lt;versión&gt;.dmg**.

## 2. Instala la app

Abre la imagen de disco descargada y arrastra **ROSilicon** a la carpeta
**Aplicaciones** que aparece al lado. Después expulsa la imagen de disco.

## 3. Ábrela por primera vez

La primera vez macOS se negará a abrirla, diciendo que no puede verificar al
desarrollador. Es lo esperado: la app no está firmada con un certificado de
desarrollador de pago de Apple, así que tu Mac no tiene forma de comprobar
quién la hizo.

1. Abre **Ajustes del Sistema › Privacidad y seguridad**.
2. Baja hasta el aviso sobre ROSilicon y pulsa **Abrir de todos modos**.
3. Abre la app otra vez y confirma.

Esto se hace una sola vez. En versiones anteriores de macOS basta con hacer clic
derecho sobre la app y elegir **Abrir**.

> Si **Abrir de todos modos** no aparece, abre el Terminal, ejecuta
> `xattr -dr com.apple.quarantine /Applications/ROSilicon.app` y abre la app a
> continuación.

## 4. Instala el juego

Pulsa **Instalar**. La app recorre una lista corta y te muestra por dónde va:

| | |
|---|---|
| **Rosetta 2** | Se comprueba primero, para que un Mac sin él lo sepa en un segundo — y no después de varios gigabytes. |
| **Entorno de Wine** | Ya viene dentro de la app. Nada que descargar. |
| **Prefijo de Wine** | El entorno Windows en el que corre el juego, creado por ti. |
| **Cliente del juego** | Unos 4,8 GB, descargados del servidor oficial, verificados y descomprimidos. |

La descarga es la parte larga. Si se interrumpe — cierras la app, se cae el
wifi — pulsa **Instalar** otra vez y sigue donde lo dejó. El botón **Registro**,
abajo en la ventana, lo muestra todo en detalle.

## 5. Juega

Pulsa **Jugar**. El juego arranca, y a partir de aquí esa es toda la rutina:
abrir ROSilicon y pulsar **Jugar**.

- Pulsa **Jugar** de nuevo con el juego abierto para abrir un **segundo
  cliente** en la misma instalación — útil para un personaje vendiendo.
- **Cerrar el juego** cierra todos los clientes a la vez.
- **Reparar** revisa la instalación y rehace lo que falte.

## Ajustes que merecen la pena

Están en el **menú `…`**, en la esquina superior derecha de la ventana, y cada
elección se recuerda.

- **Usar ⌘ para los atajos del juego** — activado por omisión. Envía ⌘A/C/V/X/Z
  al juego como los atajos de Alt que el cliente espera, en vez de los comandos
  de edición del Mac. Usa Control para copiar y pegar en el chat.
- **Usar F1–F12 como teclas de función en el juego** — **desactivado por
  omisión, y casi todo el mundo lo quiere activado.** Sin esto, F1–F12 cambian
  el brillo y el volumen en vez de usar tus barras de atajos. Activado, la fila
  superior envía F1–F12 mientras haya un cliente abierto, y vuelve a la
  normalidad en cuanto cierras el juego. Mantén `fn` para el brillo y el volumen
  mientras tanto.
- **Mostrar la actividad del juego en Discord** — activado por omisión. Tus
  amigos te ven **jugando a Ragnarok Online**, y desde hace cuánto.

## Si algo va mal

| Problema | Qué hacer |
|---|---|
| "No se puede abrir ROSilicon" o "está dañado" | Es la firma que falta, no una descarga rota — mira el paso 3. |
| Se detiene enseguida, pidiendo Rosetta | Ejecuta `softwareupdate --install-rosetta` en el Terminal y pulsa **Instalar** otra vez. |
| La descarga se atasca o falla | Pulsa **Instalar** otra vez. Reanuda y verifica lo que ya tienes. |
| F1–F12 cambian el brillo dentro del juego | Activa **Usar F1–F12 como teclas de función en el juego** en el menú `…`. |
| El juego va lento, se cierra o no arranca | Mantén **⌥ Option** con el menú `…` abierto, pon la **Traducción x87** en **Ninguna (Rosetta estándar)** y prueba otra vez. Es más lento, pero separa un fallo de la aceleración de un fallo del juego. |

¿Sigues atascado? Mantén **⌥ Option** en el menú `…`, elige **Copiar el
registro** y [abre una issue](https://github.com/victormlourenco/ROSilicon/issues)
con él pegado. El registro es lo que hace que un problema se pueda arreglar.

## Para desinstalarlo

**Vaciar la carpeta de instalación…**, en el menú `…`, mueve a la Papelera todo
lo que la app instaló, después de preguntar. Luego arrastra ROSilicon desde
Aplicaciones a la Papelera. No queda nada en ningún otro sitio de tu Mac.

---

Actualizar es solo sustituir ROSilicon en Aplicaciones por una versión más
nueva — el juego, los perfiles y los ajustes se quedan donde están.
