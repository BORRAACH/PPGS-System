// ===== CAMADA 1: PRIMITIVOS — Paleta Forno =====
// A paleta bruta do sistema, transcrita de design/Paleta Forno.html. Cada nome
// descreve a COR, nunca o papel dela na interface — "agua500", não
// "corDoSalao". Quem dá significado é o Estilo.qml.
// REGRA: nenhum arquivo fora de qml/estilo/ importa este singleton. Componente
// só conversa com a camada semântica (Estilo.*). É isso que permite trocar a
// paleta inteira — como esta troca — mexendo em dois arquivos.
// COMO A RAMPA FUNCIONA: cada família é uma escala de tonalidade em passos
// perceptuais. 50 é tinta de fundo, 300/400 é a cor cheia, 700+ é texto sobre
// a tinta. Passos de índice igual pesam o mesmo em famílias diferentes — por
// isso ouro300 e uva300 podem conviver lado a lado sem um atropelar o outro.

import QtQuick
pragma Singleton

// Terracota é a cor-mãe (o forno, o tijolo, a casca). Ouro e milho saem dela
// por rotação curta de matiz: massa e queijo. Oliva fecha o par complementar
// e é o único verde que pode ocupar área grande. Brasa é o acento quente,
// reservado a molho, urgência e erro. Pinho, água, índigo e uva têm croma
// baixo de propósito: separam domínios sem disputar com o quente.
QtObject {

    // ===== Neutros quentes: creme → carvão, nunca cinza puro =====
    readonly property color white: "#ffffff"
    readonly property color creme50: "#fffdf7"
    readonly property color areia100: "#fdf5e6"
    readonly property color areia200: "#f6e8d0"
    readonly property color areia300: "#eadaba"
    readonly property color taupe400: "#cbb595"
    readonly property color taupe500: "#a48d6e"
    readonly property color umbre600: "#7a6549"
    readonly property color umbre700: "#52432f"
    readonly property color carvao800: "#33291f"
    readonly property color carvao900: "#1b1611"
    readonly property color black: "#000000"
    // ===== Ouro — massa assada: aviso, diárias, Balcão =====
    readonly property color ouro50: "#fff9e8"
    readonly property color ouro100: "#fdedc4"
    readonly property color ouro200: "#f8db8d"
    readonly property color ouro300: "#f2c93b"
    readonly property color ouro400: "#dda63a"
    readonly property color ouro500: "#c68c24"
    readonly property color ouro600: "#a3711c"
    readonly property color ouro700: "#7d5615"
    readonly property color ouro800: "#573b0e"
    // ===== Milho — queijo: só selo, badge e realce momentâneo =====
    // Área grande em milho grita. Reservado a destaques pontuais.
    readonly property color milho50: "#fffde9"
    readonly property color milho100: "#fffa85"
    readonly property color milho200: "#f7ee3d"
    readonly property color milho300: "#e6dc00"
    readonly property color milho400: "#bfb500"
    readonly property color milho500: "#8f8800"
    // ===== Terracota — a base: Entrega, Lanches, marca =====
    readonly property color terracota50: "#fff2e4"
    readonly property color terracota100: "#fbd5a6"
    readonly property color terracota200: "#f7ad45"
    readonly property color terracota300: "#ef8730"
    readonly property color terracota400: "#e2661a"
    readonly property color terracota500: "#bb3e00"
    readonly property color terracota600: "#96320a"
    readonly property color terracota700: "#6b2507"
    // ===== Brasa — molho: cancelar, erro, exclusão, Pizzas =====
    readonly property color brasa50: "#fff0ec"
    readonly property color brasa100: "#ffcfc2"
    readonly property color brasa200: "#f5745a"
    readonly property color brasa300: "#e62200"
    readonly property color brasa400: "#cc0000"
    readonly property color brasa500: "#a80505"
    readonly property color brasa600: "#8a0000"
    readonly property color brasa700: "#5e0202"
    // ===== Oliva — manjericão: confirmar, imprimir, sucesso =====
    readonly property color oliva50: "#f3f8ea"
    readonly property color oliva100: "#ddecc6"
    readonly property color oliva200: "#b0d183"
    readonly property color oliva300: "#7ba84a"
    readonly property color oliva400: "#5f8d37"
    readonly property color oliva500: "#4b7029"
    readonly property color oliva600: "#36521c"
    // ===== Pinho — caixa: receita, lucro, total do dia =====
    readonly property color pinho50: "#edf7f0"
    readonly property color pinho100: "#c8e6d3"
    readonly property color pinho200: "#7fc79b"
    readonly property color pinho400: "#2f8d5a"
    readonly property color pinho500: "#226b43"
    readonly property color pinho600: "#17492e"
    // ===== Água — Salão, Mesa =====
    readonly property color agua50: "#e9f6f4"
    readonly property color agua100: "#bce4dd"
    readonly property color agua300: "#4fb3a5"
    readonly property color agua500: "#1f8b7d"
    readonly property color agua700: "#135f56"
    // ===== Índigo — Rede, salvar, Bebidas =====
    // Absorveu as três famílias azuis antigas (sky, blue, azure). Para
    // distinguir Bebidas, Rede e o botão Lançar entre si, use passos
    // diferentes desta rampa (100 / 300 / 500), não matizes diferentes.
    readonly property color indigo50: "#ecf2f9"
    readonly property color indigo100: "#c6daee"
    readonly property color indigo300: "#5b8fc9"
    readonly property color indigo500: "#2b5f96"
    readonly property color indigo700: "#1a3f68"
    // ===== Uva — Consulta, Açaí, Outros =====
    readonly property color uva50: "#f6eef8"
    readonly property color uva100: "#e2cbea"
    readonly property color uva300: "#a86fbd"
    readonly property color uva500: "#7d3f95"
    readonly property color uva700: "#56276a"
    // ===== Papel térmico (prévia do cupom) =====
    // Não é cor de tema: imita o papel físico da impressora.
    readonly property color paper: "#fdfbf2"
    readonly property color paperBorder: "#e8ddc0"
    // ===== Cores com alfa =====
    // scrim atrás de modal — carvão a 60%
    readonly property color overlay: "#991b1611"
    // sombra projetada de cartão — carvão a 12%
    readonly property color shadow: "#1f1b1611"
    // Fundos-tinta dos cartões do Início: o mesmo acento em 4%, 12% e 21%. A
    // transparência é intencional ali — o acento vaza pelo fundo da página.
    readonly property color ouro500Alpha04: "#0ac68c24"
    readonly property color ouro500Alpha12: "#1fc68c24"
    readonly property color ouro500Alpha21: "#36c68c24"
    readonly property color terracota500Alpha04: "#0abb3e00"
    readonly property color terracota500Alpha12: "#1fbb3e00"
    readonly property color terracota500Alpha21: "#36bb3e00"
    readonly property color oliva400Alpha04: "#0a5f8d37"
    readonly property color oliva400Alpha12: "#1f5f8d37"
    readonly property color oliva400Alpha21: "#365f8d37"
    readonly property color agua500Alpha04: "#0a1f8b7d"
    readonly property color agua500Alpha12: "#1f1f8b7d"
    readonly property color agua500Alpha21: "#361f8b7d"
}
