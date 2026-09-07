import StampedeCore

// SwiftUI dichiara a sua volta `Anchor` e `BlendMode`, e nei file di vista i due
// nomi diventano ambigui. Qui si fissa una volta per tutte quale dei due intendiamo,
// invece di scrivere `StampedeCore.` davanti a ogni occorrenza.
typealias Anchor = StampedeCore.Anchor
typealias BlendMode = StampedeCore.BlendMode
