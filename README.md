<img src="docs/icon.png" width="96" align="right" alt="">

# Stampede

Watermarking di massa per fotografi, accelerato dalla GPU. Stampa il tuo logo su
intere cartelle di foto mantenendo risoluzione, profilo colore e metadati EXIF
dell'originale, e — se vuoi — le carica su Google Drive mentre lavora.

Su un MacBook Air M4 macina **circa 19 foto da 24 megapixel al secondo** (≈470 MP/s).

C'è un'app con anteprima dal vivo e una riga di comando, sopra lo stesso motore.

![Stampede](docs/screenshot.png)

```
stampede apply ~/Scatti -o ~/Consegna --logo ~/logo.png --scale 15% --anchor bottom-right
```

Il nome viene da *stamp* — timbrare — e da quello che succede quando gli mandi
ottocento foto insieme.

## Perché esiste

uMark e simili lavorano una foto alla volta sulla CPU. Stampede tiene in volo più
immagini insieme e appoggia la composizione su Core Image, che gira su Metal: mentre
la GPU fonde il logo di una foto, la CPU sta già decodificando la successiva e
codificando la precedente. Nessuna delle due unità resta ad aspettare l'altra.

## Installazione

```bash
git clone https://github.com/unibonicolovenieri/Stampede.git
cd Stampede

./scripts/build-app.sh        # crea build/Stampede.app
cp -R build/Stampede.app /Applications/

./scripts/install.sh          # mette anche `stampede` nel PATH
stampede doctor               # verifica GPU, formati e configurazione
stampede selftest             # 76 controlli sul motore di rendering
```

Serve macOS 14 o successivo e le Command Line Tools di Xcode (`xcode-select --install`).
Xcode completo non serve. Per l'upload su Drive serve anche `rclone`
(`brew install rclone`).

Se sposti o rinomini la cartella del progetto, rilancia semplicemente uno dei due
script: si accorgono da soli che i percorsi sono cambiati e svuotano la cache di
compilazione. `.build` contiene percorsi assoluti, e senza quella pulizia Swift
fallisce lamentando un modulo `SwiftShims` mancante — un messaggio che non lascia
capire che basta cancellare una cartella.

## L'app

Trascini la cartella delle foto, scegli logo e posizione, e vedi subito il risultato:
l'anteprima usa lo stesso renderer del batch, quindi non è un'approssimazione ma
esattamente il file che verrà scritto.

- **Watermark** — logo, singolo o mosaico, le nove posizioni, dimensione, margini,
  opacità, rotazione, fusione, ombra
- **Output** — formato, qualità, 8/16 bit, profilo colore, ridimensionamento,
  nome dei file, metadati
- **Avanzate** — Google Drive, precisione del motore, foto in parallelo

Il pulsante **Comando** nella barra strumenti mostra la riga di terminale equivalente
alle impostazioni correnti, pronta da incollare in uno script.

I preset sono gli stessi file JSON per app e terminale: quello che salvi qui lo usi
con `stampede apply --preset nome`, e viceversa.

## Uso da terminale

### Una cartella, un logo

```bash
stampede apply ~/Scatti -o ~/Consegna \
  --logo ~/logo.png \
  --scale 15% --anchor bottom-right --margin 3% --opacity 0.8 --shadow
```

`-r` scende nelle sottocartelle, e l'albero viene ricreato tal quale in destinazione.

### Mosaico anti-furto per le bozze

```bash
stampede apply ~/Selezione -o ~/Bozze \
  --logo ~/logo.png --layout tile \
  --scale 13% --opacity 0.25 --tile-angle -30 --tile-spacing 0.8 \
  --resize-longest 1600
```

Il reticolo è sfalsato a mattoni e ruotato: molto più fastidioso da rimuovere in
post rispetto a un watermark singolo o a una griglia allineata.

### Flusso continuo

```bash
stampede watch ~/Ingest -o ~/Consegna --preset consegna-web --drive gdrive:Consegne/2026
```

Scarichi la scheda dentro `~/Ingest` e le foto escono già firmate e già su Drive.
Un file viene preso in carico solo quando la sua dimensione resta stabile per un
secondo e mezzo, così non si lavora mai un JPEG copiato a metà.

### Preset

```bash
# salva le impostazioni correnti
stampede apply ... --save-preset matrimoni

# oppure creane uno senza lavorare niente
stampede preset save social --logo ~/logo.png --scale 20% --resize-longest 2048

stampede preset list
stampede preset show matrimoni      # è normale JSON, modificabile a mano
```

I preset si cercano prima in `./presets` (versionabili nel repo, insieme al logo),
poi in `~/.config/stampede/presets`. In `./presets` ne trovi tre già pronti:
`consegna-web`, `antifurto`, `archivio-master`.

Le opzioni passate a riga di comando hanno sempre la precedenza sul preset, quindi
`--preset consegna-web --opacity 0.5` funziona come ci si aspetta.

## Google Drive

L'integrazione passa da [rclone](https://rclone.org), che gestisce OAuth, ritentativi
e upload ripresi molto meglio di quanto potrebbe fare questo programma.

```bash
./scripts/setup-drive.sh      # ti guida nella configurazione, una volta sola
```

Poi:

```bash
stampede apply ~/Scatti -o ~/Consegna --preset consegna-web \
  --drive gdrive:Consegne/2026-09/Rossi
```

Di default l'upload parte **appena una foto è pronta**, in parallelo con
l'elaborazione delle altre: quando la GPU ha finito, buona parte dei file è già
partita. Con `--drive-after-batch` si carica invece tutto in blocco alla fine
(più efficiente su centinaia di file piccoli).

L'albero di sottocartelle creato in locale viene ricostruito identico su Drive.

## Qualità

Il punto fermo è che l'output non deve essere peggiore dell'originale se non lo chiedi tu.

- **Risoluzione** invariata, salvo `--resize-*` esplicito.
- **Profilo colore** del sorgente riusato così com'è (`--color-space` per convertire).
- **EXIF, IPTC, GPS e XMP** copiati sull'output; `--no-metadata` per toglierli,
  `--strip-gps` per rimuovere le sole coordinate prima di consegnare a un cliente.
- **Orientamento EXIF** applicato ai pixel una volta sola e azzerato nel file,
  così nessun visualizzatore ruota la foto una seconda volta.
- **16 bit per canale** su PNG e TIFF con `--bit-depth 16`.
- **RAW** (CR2/CR3, NEF, ARW, DNG, RAF…) letti tramite il demosaicing di Core Image.
- La scrittura è **atomica**: un batch interrotto non lascia file mezzi scritti.

I logo **PDF e SVG** non vengono rasterizzati a una risoluzione fissa: li ridisegniamo
alla dimensione esatta richiesta da ogni foto, così il logo resta nitido anche su un
file da 60 megapixel.

## Prestazioni

```bash
stampede doctor --bench --bench-count 24 --bench-megapixels 24
```

La concorrenza di default è calcolata su core **e memoria**: una foto da 45 MP occupa
circa 360 MB per copia intermedia, e aprirne dieci insieme farebbe swappare la macchina
invece di andare più forte. Si può forzare con `--jobs N`.

Altre leve:

| Opzione | Effetto |
| --- | --- |
| `--precision fast` | 8 bit interni: il più veloce, adatto a JPEG di consegna |
| `--precision balanced` | half-float 16 bit (default), nessun banding percepibile |
| `--precision maximum` | float 32 bit, per master a 16 bit |
| `--blend-space srgb` | fusione come Photoshop/uMark (default) |
| `--blend-space linear` | fusione in luce lineare, fisicamente corretta |
| `--gpu-contexts N` | contesti Core Image in rotazione sulla GPU |

## Struttura

```
Sources/
  StampedeCore/          libreria riusabile — non sa niente di CLI né di GUI
    Model/                specifiche serializzabili (watermark, output, preset)
    Imaging/              pool GPU, lettura, composizione, scrittura
    Pipeline/             scoperta file ed esecuzione del batch
    Upload/               integrazione rclone
  stampede/              interfaccia a riga di comando
  StampedeApp/           app SwiftUI
presets/                  preset di esempio, versionabili
samples/                  logo dimostrativo
scripts/                  installazione, bundle .app, configurazione Drive
```

App e riga di comando sono due facce sottili sopra `StampedeCore`: le impostazioni
sono gli stessi tipi, quindi non possono divergere nel comportamento.

## Verifica

`stampede selftest` esegue 76 controlli sul motore: matematica dell'opacità,
posizionamento delle nove ancore, geometria del mosaico, ridimensionamento,
template dei nomi, percorsi remoti, e una prova completa su file veri che
ricontrolla dimensioni, EXIF e orientamento dell'output.

Non c'è un target `swift test` perché il runner di swift-testing non funziona con
le sole Command Line Tools; `selftest` copre lo stesso terreno e gira ovunque giri
il binario — anche dopo un aggiornamento di macOS, che è quando serve davvero.

L'app sa fotografare la propria finestra, così gli screenshot della documentazione
si rifanno senza lavoro manuale e senza il permesso "Registrazione schermo":

```bash
build/Stampede.app/Contents/MacOS/Stampede --capture /tmp/shot.png \
    --capture-source ~/Scatti --capture-logo ~/logo.png --capture-tab Output
```

Aggiungendo `--capture-run` la lavorazione viene eseguita davvero prima dello scatto:
è così che si verifica che il pulsante "Applica watermark" funzioni, non solo che
sia disegnato al posto giusto.

## Stato

Motore, riga di comando e app sono completi e verificati. Non ancora fatto:

- watermark di testo con segnaposto da EXIF (`{data}`, `{iso}`, `©{anno}`)
- trascinamento del logo direttamente sull'anteprima per posizionarlo a mano
- sorveglianza di una cartella dall'app (per ora è solo `stampede watch`)
- WebP in scrittura (ImageIO non lo supporta ancora su questo macOS; `doctor` lo segnala)
