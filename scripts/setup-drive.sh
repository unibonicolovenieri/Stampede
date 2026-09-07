#!/usr/bin/env bash
# Configura rclone per Google Drive. Va fatto una volta sola.
set -euo pipefail

if ! command -v rclone >/dev/null 2>&1; then
    echo "rclone non è installato."
    if command -v brew >/dev/null 2>&1; then
        read -r -p "Lo installo con Homebrew? [s/N] " reply
        case "$reply" in
            [sSyY]*) brew install rclone ;;
            *) echo "Installa rclone e rilancia questo script."; exit 1 ;;
        esac
    else
        echo "Installa Homebrew (https://brew.sh) oppure rclone a mano, poi rilancia."
        exit 1
    fi
fi

EXISTING="$(rclone listremotes 2>/dev/null | tr -d ':' | tr '\n' ' ' || true)"
if [ -n "${EXISTING// /}" ]; then
    echo "Remote già configurati: $EXISTING"
    echo
fi

cat <<'GUIDA'
Sto per aprire la configurazione interattiva di rclone.
Rispondi così:

  n                       nuovo remote
  gdrive                  nome del remote (puoi sceglierne un altro)
  drive                   tipo di storage (cerca "Google Drive" nell'elenco)
  <invio>                 client_id  — lascia vuoto
  <invio>                 client_secret — lascia vuoto
  1                       accesso completo (scope)
  <invio>                 service account — lascia vuoto
  n                       configurazione avanzata
  y                       usa il browser per autenticarti
                          → si apre Safari: accedi con il tuo account Google
  n                       NON è uno Shared Drive (rispondi y se lo è)
  y                       conferma
  q                       esci

GUIDA

read -r -p "Premi invio per continuare…" _
rclone config

echo
echo "Remote disponibili ora:"
rclone listremotes

cat <<'FINE'

Prova che funzioni (sostituisci `gdrive` con il nome che hai scelto):

  rclone lsd gdrive:

Poi passalo a EagleFoot:

  eaglefoot apply ~/Scatti -o ~/Consegna --logo ~/logo.png \
      --drive gdrive:Consegne/2026-09/Rossi

Suggerimento: crea in anticipo su Drive la cartella di destinazione se vuoi
condividerla con il cliente — rclone crea i percorsi mancanti, ma i permessi
di condivisione vanno impostati dall'interfaccia di Drive.
FINE
