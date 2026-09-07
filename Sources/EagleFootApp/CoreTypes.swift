import EagleFootCore

// SwiftUI dichiara a sua volta `Anchor` e `BlendMode`, e nei file di vista i due
// nomi diventano ambigui. Qui si fissa una volta per tutte quale dei due intendiamo,
// invece di scrivere `EagleFootCore.` davanti a ogni occorrenza.
typealias Anchor = EagleFootCore.Anchor
typealias BlendMode = EagleFootCore.BlendMode
