# CronBuddy

O **CronBuddy** é um gerenciador moderno e nativo de `cron jobs` para macOS, construído inteiramente em Python. Diferente das soluções tradicionais de terminal, o CronBuddy oferece uma interface gráfica minimalista (com suporte a Dark Mode nativo), integração direta à barra de menus (Menu Bar) do Mac, e um gerenciador de arquivos embutido para lidar facilmente com logs, scripts e templates de comandos.

## Funcionalidades

- **Gerenciador Visual de Cron:** Visualize todos os seus agendamentos ativos e inativos em cards modernos e estilosos.
- **Ícone na Barra de Menus (Menu Bar):** O aplicativo roda silenciosamente no topo da sua tela, utilizando a biblioteca `rumps` focada no ecossistema Apple.
- **Agendamentos Intuitivos:** Em vez de tentar lembrar a sintaxe do cron (`* * * * *`), a interface oferece caixas de seleção como "Every Day at Midnight", que traduzem a sua vontade em código automaticamente.
- **Templates Dinâmicos:** A pasta `templates/` no projeto serve como uma galeria de opções de comandos úteis (ex: Limpar a lixeira, Ping, Verificar Logs de CPU). Adicione seus scripts lá e a interface absorverá o template na hora.
- **File Manager Multi-Abas:** Com apenas um clique, visualize, crie, delete e edite scripts criados por você na sua pasta local. Contempla abas exclusivas para:
  - Scripts em Shell (`~/CronBuddyScripts/shell`)
  - Scripts em Python (`~/CronBuddyScripts/python`)
  - Logs de execução (`~/CronBuddyScripts/logs`)
  - Seus Templates Personalizados (`/templates`)

## Pré-requisitos e Instalação

1. Certifique-se de ter o Python 3 instalado no seu macOS. É recomendável utilizar um ambiente virtual (`venv`).
2. Se o Python reclamar sobre não ter o pacote de interface (`_tkinter` missing), certifique-se de instalá-lo via Homebrew (ex: `brew install python-tk@3.14`).
3. Clone este repositório e instale as dependências:

```bash
git clone https://github.com/lucasrafaldini/cronbuddy.git
cd cronbuddy
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## Como Executar

O fluxo de trabalho recomendado é inciar o aplicativo sempre através do **Menu Bar**:

```bash
python menubar.py
```
*(Um ícone aparecerá no canto superior direito do seu Mac. Clique nele e selecione "Open CronBuddy" para visualizar a interface principal).*

### Modo de Teste
Se você quiser validar um comando rapidamente, inicie o app com a flag de teste:

```bash
python menubar.py --test
```
Essa flag adicionará uma opção especial **"One Minute From Now (Test)"** no momento em que você for escolher o horário de um Cron Job. Ela agendará o comando para rodar exatamente no minuto seguinte!

## Estrutura de Diretórios

O CronBuddy organiza arquivos em dois lugares principais:

1. **Repositório do Projeto:** Onde o código-fonte mora. Aqui você também encontra a pasta `templates/` com scripts úteis nativos (`.sh`).
2. **Diretório do Usuário (`~/CronBuddyScripts`):** A pasta na home do seu usuário, com as devidas separações (`/shell`, `/python`, `/logs`) usada para garantir que nenhum script seu seja deletado por engano ou misturado com o código raiz.

## Bibliotecas Principais Utilizadas
- `python-crontab`: Para interagir com o agendador nativo do sistema Unix/Mac.
- `CustomTkinter`: Interface gráfica de usuário moderna, dark-mode native.
- `rumps`: Integração impecável da barra de menus superior do macOS em pouquíssimas linhas de código.
