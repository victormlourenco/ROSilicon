# Primeiros Passos

[🇺🇸 English](Getting-Started) · 🇧🇷 Português · [🇪🇸 Español](Primeros-Pasos)

O ROSilicon instala o Ragnarok Online LATAM no seu Mac e roda o jogo. Você não
precisa de Windows, de Boot Camp nem de saber nada sobre o Wine — o aplicativo
já carrega tudo, menos o cliente do jogo, que ele baixa para você.

<p align="center">
  <img src="https://raw.githubusercontent.com/wiki/victormlourenco/ROSilicon/images/launcher-pt-BR.png" width="620" alt="A janela do ROSilicon, pronta para jogar">
</p>

## Antes de começar

- Um Mac com **Apple Silicon** — M1, M2, M3, M4 ou mais recente. Macs com Intel
  não são compatíveis. (Menu Apple › **Sobre Este Mac**: a linha do chip precisa
  dizer *Apple*.)
- **macOS 14 Sonoma** ou mais recente.
- **Rosetta 2.** Se você nunca instalou, abra o Terminal e execute
  `softwareupdate --install-rosetta`. O aplicativo também verifica e avisa em um
  segundo se estiver faltando.
- Cerca de **12 GB livres** no disco. Só o cliente do jogo tem uns 4,8 GB para
  baixar.

## 1. Baixe

Acesse a [página de versões](https://github.com/victormlourenco/ROSilicon/releases/latest)
e baixe o **ROSilicon-&lt;versão&gt;.dmg**.

## 2. Instale o aplicativo

Abra a imagem de disco baixada e arraste o **ROSilicon** para a pasta
**Aplicativos** que aparece ao lado. Depois ejete a imagem de disco.

## 3. Abra pela primeira vez

Na primeira vez o macOS vai se recusar a abrir, dizendo que não consegue
verificar o desenvolvedor. Isso é esperado: o aplicativo não é assinado com um
certificado pago de desenvolvedor da Apple, então o seu Mac não tem como
confirmar quem o criou.

1. Abra os **Ajustes do Sistema › Privacidade e Segurança**.
2. Role até o aviso sobre o ROSilicon e clique em **Abrir Assim Mesmo**.
3. Abra o aplicativo de novo e confirme.

Isso é feito uma única vez. Em versões mais antigas do macOS, basta clicar no
aplicativo com o botão direito e escolher **Abrir**.

> Se **Abrir Assim Mesmo** não aparecer, abra o Terminal, execute
> `xattr -dr com.apple.quarantine /Applications/ROSilicon.app` e abra o
> aplicativo em seguida.

## 4. Instale o jogo

Clique em **Instalar**. O aplicativo percorre uma lista curta e mostra em que
ponto está:

| | |
|---|---|
| **Rosetta 2** | Verificado primeiro, para que um Mac sem ele saiba na hora — e não depois de vários gigabytes. |
| **Runtime do Wine** | Já vem dentro do aplicativo. Nada para baixar. |
| **Prefixo do Wine** | O ambiente Windows em que o jogo roda, criado para você. |
| **Cliente do jogo** | Cerca de 4,8 GB, baixados do servidor oficial, verificados e extraídos. |

O download é a parte demorada. Se ele for interrompido — você fecha o
aplicativo, o Wi-Fi cai — clique em **Instalar** de novo e ele continua de onde
parou. O botão **Registro**, embaixo da janela, mostra tudo em detalhe.

## 5. Jogue

Clique em **Jogar**. O jogo abre, e daqui em diante essa é a rotina inteira:
abrir o ROSilicon e clicar em **Jogar**.

- Clique em **Jogar** de novo com o jogo aberto para abrir um **segundo
  cliente** na mesma instalação — útil para um personagem vendendo.
- **Encerrar jogo** fecha todos os clientes de uma vez.
- **Reparar** confere a instalação e refaz o que estiver faltando.

## Ajustes que valem a pena

Eles ficam no **menu `…`**, no canto superior direito da janela, e cada escolha
é lembrada.

- **Usar ⌘ nos atalhos do jogo** — ligado por padrão. Manda ⌘A/C/V/X/Z para o
  jogo como os atalhos de Alt que o cliente espera, em vez dos comandos de
  edição do Mac. Use Control para copiar e colar no chat.
- **Usar F1–F12 como teclas de função no jogo** — **desligado por padrão, e a
  maioria das pessoas quer ligar.** Sem isso, F1–F12 mudam o brilho e o volume
  em vez de acionar as barras de atalho. Ligado, a fileira de cima manda F1–F12
  enquanto houver um cliente aberto, e volta ao normal assim que você fecha o
  jogo. Segure `fn` para brilho e volume nesse meio-tempo.
- **Mostrar a atividade do jogo no Discord** — ligado por padrão. Seus amigos
  veem você **jogando Ragnarok Online**, e há quanto tempo.

## Se algo der errado

| Problema | O que fazer |
|---|---|
| "O ROSilicon não pode ser aberto" ou "está danificado" | É a assinatura que falta, não um download corrompido — veja o passo 3. |
| Para na hora, pedindo o Rosetta | Execute `softwareupdate --install-rosetta` no Terminal e clique em **Instalar** de novo. |
| O download trava ou falha | Clique em **Instalar** de novo. Ele continua e confere o que já baixou. |
| F1–F12 mudam o brilho durante o jogo | Ligue **Usar F1–F12 como teclas de função no jogo** no menu `…`. |
| O jogo está lento, trava ou não abre | Segure **⌥ Option** com o menu `…` aberto, mude a **Tradução x87** para **Nenhuma (Rosetta padrão)** e tente de novo. É mais lento, mas separa um problema da aceleração de um problema do jogo. |
| A tela fica preta, ou algo aparece errado | Segure **⌥ Option** com o menu `…` aberto e mude o **Driver Vulkan** para **MoltenVK**, o driver que o launcher usava antes do macOS 26. Vale a partir da próxima vez que você apertar **Jogar**. |

Continua travado? Segure **⌥ Option** no menu `…`, escolha **Copiar registro** e
[abra uma issue](https://github.com/victormlourenco/ROSilicon/issues) com ele
colado. É o registro que torna um problema resolvível.

## Para remover

**Limpar pasta de instalação…**, no menu `…`, move para o Lixo tudo o que o
aplicativo instalou, depois de perguntar. Em seguida arraste o ROSilicon de
Aplicativos para o Lixo. Não fica nada em outro lugar do seu Mac.

---

Atualizar é só trocar o ROSilicon em Aplicativos por uma versão mais nova — o
jogo, os perfis e os ajustes continuam onde estão.
