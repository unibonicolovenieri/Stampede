# Da includere con `source` prima di ogni `swift build`.
#
# La cartella .build contiene percorsi assoluti: se il progetto viene spostato o
# rinominato, la cache dei moduli punta a una cartella che non esiste più e la
# compilazione muore con "missing required module 'SwiftShims'". Non è un guasto,
# ma il messaggio non lo dice, quindi ce ne accorgiamo noi e ripuliamo.

prepare_build() {
    local root="$1"
    local stamp="$root/.build/.stampede-root"

    if [ -f "$stamp" ]; then
        local previous
        previous="$(cat "$stamp")"
        if [ "$previous" != "$root" ]; then
            echo "Il progetto si è spostato:"
            echo "  da  $previous"
            echo "  a   $root"
            echo "Svuoto la cache di compilazione, altrimenti la build fallirebbe."
            rm -rf "$root/.build" "$root/build"
        fi
    fi

    mkdir -p "$root/.build"
    printf '%s' "$root" > "$stamp"
}
