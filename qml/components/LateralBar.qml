import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import estilo 1.0

Rectangle {
    id: sideBar
    Layout.fillHeight: true
    Layout.preferredWidth: 70
    Layout.rightMargin: Estilo.preenchimento.pequeno
    // Nada (texto, botão, etc.) pode ser desenhado além dos limites da
    // barra lateral — sem isso, textos mais largos que o espaço disponível
    // vazavam para fora do retângulo.
    clip: true
    // Poucos tons mais escuro que o fundo das páginas (#f8f9fa, usado em
    // Balcao.qml, Pedido.qml, Entregarega.qml etc.), em vez de uma cor solta.
    color: Qt.darker(Estilo.cores.fundoPagina, 1.8)

    property StackView stackView: null

    ColumnLayout {
        anchors.fill: parent
        // Padding vertical/horizontal e spacing entre os grupos espelham
        // Bar.vPadding (padding.large), BarWrapper.padding (padding.smaller)
        // e o "spacing: Appearance.spacing.normal" do Bar.qml do caelestia.
        anchors.topMargin: Estilo.preenchimento.grande
        anchors.bottomMargin: Estilo.preenchimento.grande
        anchors.leftMargin: Estilo.preenchimento.menor
        anchors.rightMargin: Estilo.preenchimento.menor
        spacing: Estilo.espacamento.normal

        // --- CÁPSULA DE NAVEGAÇÃO PRINCIPAL (Estilo Ícones Agrupados) ---
        Rectangle {
            id: capsulaNavegacao

            Layout.fillWidth: true
            // Padding vertical igual ao usado pelos grupos (Workspaces/Tray)
            // do Bar.qml do caelestia: Appearance.padding.small em cima e embaixo.
            Layout.preferredHeight: colNavegacao.implicitHeight + Estilo.preenchimento.pequeno * 2
            // Levemente mais clara que o fundo do LateralBar, em vez do
            // tom azulado escuro de antes.
            color: Qt.lighter(sideBar.color, 108)
            // Raio "cheio" (pílula) — mesmo usado nos grupos do Bar.qml do
            // caelestia (radius: Appearance.rounding.full); o Qt limita
            // automaticamente ao raio máximo possível (metade do menor lado).
            radius: Estilo.rounding.cheio

            // Itens de navegação: ícone, texto do tooltip, página de destino
            // (vazia para o botão Home, que apenas volta ao topo da pilha) e
            // objectName da tela para evitar push duplicado da mesma página.
            ListModel {
                id: modeloNavegacao
                ListElement { icone: "fa6s.house"; textoTooltip: "Início"; pagina: ""; nomeTela: "" }
                ListElement { icone: "fa6s.bag-shopping"; textoTooltip: "Balcão"; pagina: "../pages/balcao/Balcao.qml"; nomeTela: "telaBalcao" }
                ListElement { icone: "fa6s.motorcycle"; textoTooltip: "Entrega"; pagina: "../pages/entrega/Entrega.qml"; nomeTela: "telaEntrega" }
                ListElement { icone: "fa6s.utensils"; textoTooltip: "Salão"; pagina: "../pages/salao/Salao.qml"; nomeTela: "telaSalao" }
                ListElement { icone: "fa6s.magnifying-glass"; textoTooltip: "Consulta"; pagina: "../pages/consulta/Consulta.qml"; nomeTela: "telaConsulta" }
                ListElement { icone: "fa6s.cash-register"; textoTooltip: "Fechamento"; pagina: "../pages/fechamento/Fechamento.qml"; nomeTela: "telaFechamento" }
                ListElement { icone: "fa6s.globe"; textoTooltip: "Rede"; pagina: "../pages/rede/Rede.qml"; nomeTela: "telaRede" }
            }

            ColumnLayout {
                id: colNavegacao
                anchors.centerIn: parent
                width: parent.width - Estilo.preenchimento.pequeno * 2

                Repeater {
                    model: modeloNavegacao

                    delegate: Button {
                        id: btnNav
                        Layout.fillWidth: true
                        // Ícone (24) + padding.normal dos dois lados — mesma
                        // relação usada em Power.qml (icon.implicitHeight + padding.small * 2).
                        implicitHeight: 24 + Estilo.preenchimento.normal * 2

                        background: Rectangle {
                            color: btnNav.hovered ? Qt.darker(capsulaNavegacao.color, 1.4) : "transparent"
                            radius: Estilo.rounding.cheio
                        }

                        ToolTip {
                            text: textoTooltip
                            visible: btnNav.hovered
                            delay: 400
                            padding: Estilo.preenchimento.normal
                            x: btnNav.width + Estilo.espacamento.pequeno
                            y: (btnNav.height - height) / 2

                            background: Rectangle {
                                radius: Estilo.rounding.popup
                                color: capsulaNavegacao.color
                                border.color: Estilo.cores.bordaCard
                                border.width: 1
                            }
                        }

                        contentItem: Item {
                            anchors.fill: parent
                            Icone {
                                nome: icone
                                cor: Estilo.cores.texto
                                tamanho: 22
                                anchors.centerIn: parent
                            }
                        }

                        onClicked: {
                            if (pagina === "") {
                                if (sideBar.stackView) {
                                    sideBar.stackView.pop(null);
                                }
                            } else if (sideBar.stackView && sideBar.stackView.currentItem && sideBar.stackView.currentItem.objectName !== nomeTela) {
                                // replace(null, ...) troca a pilha INTEIRA
                                // pela página nova — não push(), que só
                                // empilha por cima sem nunca destruir nada.
                                // Navegação aqui é sempre entre telas
                                // irmãs (Balcão, Entrega, Salão...), nunca
                                // um "entrar mais fundo" que precise voltar
                                // depois — com push(), um dia inteiro
                                // clicando entre elas (sem nunca voltar pro
                                // Início, que é o único botão que limpa a
                                // pilha) acumulava uma instância nova a
                                // cada clique, cada uma com seu próprio
                                // ListModel/Timer/conexões, sem nunca
                                // liberar memória — exatamente o tipo de
                                // vazamento que trava máquinas fracas ao
                                // longo do expediente.
                                sideBar.stackView.replace(null, pagina, {}, StackView.Immediate);
                            }
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        } // Espaçador Flexível

        // --- CÁPSULA INFERIOR (Atalhos/Rodapé estilo Imagem) ---
        Rectangle {
            id: capsulaRodape

            Layout.fillWidth: true
            implicitHeight: colFooter.implicitHeight + Estilo.preenchimento.pequeno * 2
            color: Qt.lighter(sideBar.color, 108)
            radius: Estilo.rounding.cheio

            // Telas de manutenção do sistema (o que se mexe de vez em quando),
            // separadas da cápsula de cima, que é o fluxo de atendimento do
            // dia a dia: o cardápio em si (data/cardapio/*.json) e o estilo
            // da comanda impressa. Mesmos campos e mesmo comportamento de
            // clique de modeloNavegacao acima.
            ListModel {
                id: modeloRodape
                ListElement { icone: "fa6s.book-open"; textoTooltip: "Cardápio"; pagina: "../pages/cardapio/Cardapio.qml"; nomeTela: "telaCardapio" }
                ListElement { icone: "fa6s.gear"; textoTooltip: "Configurações"; pagina: "../pages/configuracoes/Configuracoes.qml"; nomeTela: "telaConfiguracoes" }
            }

            ColumnLayout {
                id: colFooter
                anchors.centerIn: parent
                width: parent.width - Estilo.preenchimento.pequeno * 2
                spacing: Estilo.espacamento.menor

                Repeater {
                    model: modeloRodape

                    delegate: Button {
                        id: btnRodape

                        Layout.fillWidth: true
                        implicitHeight: 24 + Estilo.preenchimento.normal * 2

                        background: Rectangle {
                            color: btnRodape.hovered ? Qt.darker(capsulaRodape.color, 1.4) : "transparent"
                            radius: Estilo.rounding.cheio
                        }

                        ToolTip {
                            text: textoTooltip
                            visible: btnRodape.hovered
                            delay: 400
                            padding: Estilo.preenchimento.normal
                            x: btnRodape.width + Estilo.espacamento.pequeno
                            y: (btnRodape.height - height) / 2

                            background: Rectangle {
                                radius: Estilo.rounding.popup
                                color: capsulaRodape.color
                                border.color: Estilo.cores.bordaCard
                                border.width: 1
                            }
                        }

                        contentItem: Item {
                            anchors.fill: parent
                            Icone {
                                nome: icone
                                cor: Estilo.cores.texto
                                tamanho: 22
                                anchors.centerIn: parent
                            }
                        }

                        onClicked: {
                            if (sideBar.stackView && sideBar.stackView.currentItem && sideBar.stackView.currentItem.objectName !== nomeTela) {
                                // Ver o mesmo comentário no Repeater de
                                // modeloNavegacao acima.
                                sideBar.stackView.replace(null, pagina, {}, StackView.Immediate);
                            }
                        }
                    }
                }
            }
        }
    }
}
