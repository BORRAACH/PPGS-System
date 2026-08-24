import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

Rectangle {
    id: sideBar

    property StackView stackView: null
    // Largura do ícone (22) mais o respiro dos dois lados. Em tela estreita a
    // barra afina em vez de sumir: navegar entre telas é a única coisa que
    // precisa estar sempre ao alcance, e cada pixel devolvido aqui vira
    // espaço de formulário do outro lado.
    readonly property int larguraBarra: Responsivo.compacto ? 52 : 70

    Layout.fillHeight: true
    Layout.preferredWidth: larguraBarra
    Layout.rightMargin: Estilo.global.padding.xs
    // Nada (texto, botão, etc.) pode ser desenhado além dos limites da
    // barra lateral — sem isso, textos mais largos que o espaço disponível
    // vazavam para fora do retângulo.
    clip: true
    // Poucos tons mais escuro que o fundo das páginas (#f8f9fa, usado em
    // Balcao.qml, Pedido.qml, Entregarega.qml etc.), em vez de uma cor solta.
    color: Estilo.global.chrome

    ColumnLayout {
        // Espaçador Flexível

        anchors.fill: parent
        // Padding vertical/horizontal e spacing entre os grupos espelham
        // Bar.vPadding (padding.large), BarWrapper.padding (padding.smaller)
        // e o "spacing: Appearance.spacing.normal" do Bar.qml do caelestia.
        anchors.topMargin: Estilo.global.padding.xl
        anchors.bottomMargin: Estilo.global.padding.xl
        anchors.leftMargin: Estilo.global.padding.sm
        anchors.rightMargin: Estilo.global.padding.sm
        spacing: Estilo.global.spacing.lg

        // --- CÁPSULA DE NAVEGAÇÃO PRINCIPAL (Estilo Ícones Agrupados) ---
        Rectangle {
            id: capsulaNavegacao

            Layout.fillWidth: true
            // Padding vertical igual ao usado pelos grupos (Workspaces/Tray)
            // do Bar.qml do caelestia: Appearance.padding.small em cima e embaixo.
            Layout.preferredHeight: colNavegacao.implicitHeight + Estilo.global.padding.xs * 2
            // Levemente mais clara que o fundo do LateralBar, em vez do
            // tom azulado escuro de antes.
            color: Qt.lighter(sideBar.color, 108)
            // Raio "cheio" (pílula) — mesmo usado nos grupos do Bar.qml do
            // caelestia (radius: Appearance.rounding.full); o Qt limita
            // automaticamente ao raio máximo possível (metade do menor lado).
            radius: Estilo.global.radius.pill

            // Itens de navegação: ícone, texto do tooltip, página de destino
            // e objectName da tela — evita trocar de novo pra mesma página
            // já aberta (ver onClicked abaixo).
            ListModel {
                id: modeloNavegacao

                ListElement {
                    icone: "fa6s.house"
                    textoTooltip: "Início"
                    pagina: "../pages/inicio/Inicio.qml"
                    nomeTela: "pageHome"
                }

                ListElement {
                    icone: "fa6s.bag-shopping"
                    textoTooltip: "Balcão"
                    pagina: "../pages/balcao/Balcao.qml"
                    nomeTela: "telaBalcao"
                }

                ListElement {
                    icone: "fa6s.motorcycle"
                    textoTooltip: "Entrega"
                    pagina: "../pages/entrega/Entrega.qml"
                    nomeTela: "telaEntrega"
                }

                ListElement {
                    icone: "fa6s.utensils"
                    textoTooltip: "Salão"
                    pagina: "../pages/salao/Salao.qml"
                    nomeTela: "telaSalao"
                }

                ListElement {
                    icone: "fa6s.magnifying-glass"
                    textoTooltip: "Consulta"
                    pagina: "../pages/consulta/Consulta.qml"
                    nomeTela: "telaConsulta"
                }

                ListElement {
                    icone: "fa6s.cash-register"
                    textoTooltip: "Fechamento"
                    pagina: "../pages/fechamento/Fechamento.qml"
                    nomeTela: "telaFechamento"
                }

                ListElement {
                    icone: "fa6s.globe"
                    textoTooltip: "Rede"
                    pagina: "../pages/rede/Rede.qml"
                    nomeTela: "telaRede"
                }

            }

            ColumnLayout {
                id: colNavegacao

                anchors.centerIn: parent
                width: parent.width - Estilo.global.padding.xs * 2

                Repeater {
                    model: modeloNavegacao

                    delegate: Button {
                        id: btnNav

                        Layout.fillWidth: true
                        // Ícone (24) + padding.normal dos dois lados — mesma
                        // relação usada em Power.qml (icon.implicitHeight + padding.small * 2).
                        // O padding encolhe junto com o resto em tela pequena,
                        // mas o botão não desce do alvo mínimo de toque: aqui
                        // quem aponta é o dedo, e um alvo menor que isso vira
                        // erro de navegação no meio do atendimento.
                        implicitHeight: Math.max(Responsivo.alvoToque, 24 + Estilo.global.padding.md * 2)
                        onClicked: {
                            // replace(null, ...) troca a pilha INTEIRA
                            // pela página nova — não push(), que só
                            // empilha por cima sem nunca destruir nada.
                            // Navegação aqui é sempre entre telas
                            // irmãs (Início, Balcão, Entrega, Salão...),
                            // nunca um "entrar mais fundo" que precise
                            // voltar depois, então Início não é mais um
                            // caso especial (pop(null)) — é só mais um
                            // destino, como qualquer outro (ver
                            // qml/pages/inicio/Inicio.qml). Com push(),
                            // um dia inteiro clicando entre telas sem
                            // nunca "voltar" acumulava uma instância
                            // nova a cada clique, cada uma com seu
                            // próprio ListModel/Timer/conexões, sem
                            // nunca liberar memória — exatamente o tipo
                            // de vazamento que trava máquinas fracas ao
                            // longo do expediente.

                            if (sideBar.stackView && sideBar.stackView.currentItem && sideBar.stackView.currentItem.objectName !== nomeTela)
                                sideBar.stackView.replace(null, pagina, {
                            }, StackView.Immediate);

                        }

                        ToolTip {
                            text: textoTooltip
                            visible: btnNav.hovered
                            delay: 400
                            padding: Estilo.global.padding.md
                            x: btnNav.width + Estilo.global.spacing.xs
                            y: (btnNav.height - height) / 2

                            background: Rectangle {
                                radius: Estilo.global.radius.xl
                                color: capsulaNavegacao.color
                                border.color: Estilo.global.borderCard
                                border.width: Estilo.global.borderWidth.hairline
                            }

                        }

                        background: Rectangle {
                            color: btnNav.hovered ? Qt.darker(capsulaNavegacao.color, 1.4) : "transparent"
                            radius: Estilo.global.radius.pill
                        }

                        contentItem: Item {
                            anchors.fill: parent

                            Icone {
                                nome: icone
                                cor: Estilo.global.text
                                tamanho: 22
                                anchors.centerIn: parent
                            }

                        }

                    }

                }

            }

        }

        Item {
            Layout.fillHeight: true
        }

        // --- CÁPSULA INFERIOR (Atalhos/Rodapé estilo Imagem) ---
        Rectangle {
            id: capsulaRodape

            Layout.fillWidth: true
            implicitHeight: colFooter.implicitHeight + Estilo.global.padding.xs * 2
            color: Qt.lighter(sideBar.color, 1)
            radius: Estilo.global.radius.pill

            // Telas de manutenção do sistema (o que se mexe de vez em quando),
            // separadas da cápsula de cima, que é o fluxo de atendimento do
            // dia a dia: o cardápio em si (data/cardapio/*.json) e o estilo
            // da comanda impressa. Mesmos campos e mesmo comportamento de
            // clique de modeloNavegacao acima.
            ListModel {
                id: modeloRodape

                ListElement {
                    icone: "fa6s.book-open"
                    textoTooltip: "Cardápio"
                    pagina: "../pages/cardapio/Cardapio.qml"
                    nomeTela: "telaCardapio"
                }

                ListElement {
                    icone: "fa6s.gear"
                    textoTooltip: "Configurações"
                    pagina: "../pages/configuracoes/Configuracoes.qml"
                    nomeTela: "telaConfiguracoes"
                }

            }

            ColumnLayout {
                id: colFooter

                anchors.centerIn: parent
                width: parent.width - Estilo.global.padding.xs * 2
                spacing: Estilo.global.spacing.md

                Repeater {
                    model: modeloRodape

                    delegate: Button {
                        id: btnRodape

                        Layout.fillWidth: true
                        // O padding encolhe junto com o resto em tela pequena,
                        // mas o botão não desce do alvo mínimo de toque: aqui
                        // quem aponta é o dedo, e um alvo menor que isso vira
                        // erro de navegação no meio do atendimento.
                        implicitHeight: Math.max(Responsivo.alvoToque, 24 + Estilo.global.padding.md * 2)
                        onClicked: {
                            // Ver o mesmo comentário no Repeater de
                            // modeloNavegacao acima.

                            if (sideBar.stackView && sideBar.stackView.currentItem && sideBar.stackView.currentItem.objectName !== nomeTela)
                                sideBar.stackView.replace(null, pagina, {
                            }, StackView.Immediate);

                        }

                        ToolTip {
                            text: textoTooltip
                            visible: btnRodape.hovered
                            delay: 400
                            padding: Estilo.global.padding.md
                            x: btnRodape.width + Estilo.global.spacing.xs
                            y: (btnRodape.height - height) / 2

                            background: Rectangle {
                                radius: Estilo.global.radius.xl
                                color: capsulaRodape.color
                                border.color: Estilo.global.borderCard
                                border.width: Estilo.global.borderWidth.hairline
                            }

                        }

                        background: Rectangle {
                            color: btnRodape.hovered ? Qt.darker(capsulaRodape.color, 1.4) : "transparent"
                            radius: Estilo.global.radius.pill
                        }

                        contentItem: Item {
                            anchors.fill: parent

                            Icone {
                                nome: icone
                                cor: Estilo.global.text
                                tamanho: 22
                                anchors.centerIn: parent
                            }

                        }

                    }

                }

            }

        }

    }

}
