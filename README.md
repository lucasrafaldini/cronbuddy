# CronBuddy

<p align="center">
  <img src="assets/cronbuddy-slogan.png" alt="CronBuddy Logo" width="600">
</p>

<p align="center">
  <a href="#english">English</a> | 
  <a href="#português">Português</a> | 
  <a href="#español">Español</a>
</p>

---

<a id="english"></a>
## English

**CronBuddy** is a modern and native `cron job` manager for macOS, built entirely in Python. Unlike traditional terminal solutions, CronBuddy offers a minimalist graphical interface (with native Dark Mode support), direct integration with the Mac's Menu Bar, and a built-in file manager to easily handle logs, scripts, and command templates.

### Features

- **Visual Cron Manager:** Visualize all of your active and inactive schedules in modern and stylish cards.
- **Menu Bar Icon:** The app runs silently at the top of your screen, using the `rumps` library tailored for the Apple ecosystem.
- **Intuitive Scheduling:** Instead of trying to remember the cron syntax (`* * * * *`), the interface offers easy dropdowns/selections like "Every Day at Midnight", which automatically translate your wishes into code.
- **Dynamic Templates:** The `templates/` folder in the project serves as a gallery of useful commands (e.g., Empty trash, Ping, Check CPU Logs). Add your scripts there and the interface will absorb the template instantly.
- **Multi-Tab File Manager:** With just one click, view, create, delete, and edit scripts created by you in your local folder. It features exclusive tabs for:
  - Shell Scripts (`~/CronBuddyScripts/shell`)
  - Python Scripts (`~/CronBuddyScripts/python`)
  - Execution Logs (`~/CronBuddyScripts/logs`)
  - Your Custom Templates (`/templates`)
- **Start with macOS (Autostart):** Enable or disable starting CronBuddy automatically at system login directly via a modern checkbox in the sidebar.

### Prerequisites and Installation

1. Make sure you have Python 3 installed on your macOS. Using a virtual environment (`venv`) is highly recommended.
2. If Python complains about the missing GUI package (`_tkinter` missing), be sure to install it via Homebrew (e.g., `brew install python-tk@3.14`).
3. Clone this repository and install the dependencies:

```bash
git clone https://github.com/lucasrafaldini/cronbuddy.git
cd cronbuddy
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### How to Run (Development)

The recommended workflow for development is to start the application through the terminal:

```bash
python menubar.py
```
*(An icon will appear in the top-right corner of your Mac).*

### Generating the Executable (.app) for macOS

If you want to turn CronBuddy into a native macOS app (without needing to open the terminal):

1. Make sure you are inside the active virtual environment.
2. Run the build command:

```bash
./build_app.sh
```

The app will be generated inside the `dist/CronBuddy.app` folder. You can drag it into your **Applications** folder and run it like any other Mac app.

#### Test Mode
If you want to validate a command quickly, start the app with the test flag:

```bash
python menubar.py --test
```
This flag will add a special **"One Minute From Now (Test)"** option when choosing the time for a Cron Job. It will schedule the command to run exactly in the following minute!

### Directory Structure

CronBuddy organizes files in two main locations:

1. **Project Repository:** Where the source code lives. Here you will also find the `templates/` folder with useful native scripts (`.sh`, `.py`).
2. **User Directory (`~/CronBuddyScripts`):** The folder in your user's home directory, with proper separations (`/shell`, `/python`, `/logs`) used to ensure none of your scripts are deleted by mistake or mixed with the root code.

### Main Libraries Used
- `python-crontab`: To interact with the Unix/Mac native cron scheduler.
- `CustomTkinter`: Modern, dark-mode native Graphical User Interface.
- `rumps`: Flawless integration with the macOS top menu bar in very few lines of code.

---

<a id="português"></a>
## Português

O **CronBuddy** é um gerenciador moderno e nativo de `cron jobs` para macOS, construído inteiramente em Python. Diferente das soluções tradicionais de terminal, o CronBuddy oferece uma interface gráfica minimalista (com suporte a Dark Mode nativo), integração direta à barra de menus (Menu Bar) do Mac, e um gerenciador de arquivos embutido para lidar facilmente com logs, scripts e templates de comandos.

### Funcionalidades

- **Gerenciador Visual de Cron:** Visualize todos os seus agendamentos ativos e inativos em cards modernos e estilosos.
- **Ícone na Barra de Menus (Menu Bar):** O aplicativo roda silenciosamente no topo da sua tela, utilizando a biblioteca `rumps` focada no ecossistema Apple.
- **Agendamentos Intuitivos:** Em vez de tentar lembrar a sintaxe do cron (`* * * * *`), a interface oferece caixas de seleção como "Every Day at Midnight", que traduzem a sua vontade em código automaticamente.
- **Templates Dinâmicos:** A pasta `templates/` no projeto serve como uma galeria de opções de comandos úteis (ex: Limpar a lixeira, Ping, Verificar Logs de CPU). Adicione seus scripts lá e a interface absorverá o template na hora.
- **File Manager Multi-Abas:** Com apenas um clique, visualize, crie, delete e edite scripts criados por você na sua pasta local. Contempla abas exclusivas para:
  - Scripts em Shell (`~/CronBuddyScripts/shell`)
  - Scripts em Python (`~/CronBuddyScripts/python`)
  - Logs de execução (`~/CronBuddyScripts/logs`)
  - Seus Templates Personalizados (`/templates`)
- **Iniciar com o macOS (Autostart):** Habilite ou desabilite o início automático do CronBuddy com o login do sistema diretamente a partir de um checkbox moderno na barra lateral.

### Pré-requisitos e Instalação

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

### Como Executar (Desenvolvimento)

O fluxo de trabalho recomendado para desenvolvimento é iniciar o aplicativo através do terminal:

```bash
python menubar.py
```
*(Um ícone aparecerá no canto superior direito do seu Mac).*

### Gerando o Executável (.app) para macOS

Se você deseja transformar o CronBuddy em um aplicativo nativo do macOS (sem precisar abrir o terminal):

1. Certifique-se de estar com o ambiente virtual ativo.
2. Execute o comando de build:

```bash
./build_app.sh
```

O aplicativo será gerado na pasta `dist/CronBuddy.app`. Você pode arrastá-lo para sua pasta de **Aplicações** e executá-lo como qualquer outro app do Mac.

#### Modo de Teste
Se você quiser validar um comando rapidamente, inicie o app com a flag de teste:

```bash
python menubar.py --test
```
Essa flag adicionará uma opção especial **"One Minute From Now (Test)"** no momento em que você for escolher o horário de um Cron Job. Ela agendará o comando para rodar exatamente no minuto seguinte!

### Estrutura de Diretórios

O CronBuddy organiza arquivos em dois lugares principais:

1. **Repositório do Projeto:** Onde o código-fonte mora. Aqui você também encontra a pasta `templates/` com scripts úteis nativos (`.sh`, `.py`).
2. **Diretório do Usuário (`~/CronBuddyScripts`):** A pasta na home do seu usuário, com as devidas separações (`/shell`, `/python`, `/logs`) usada para garantir que nenhum script seu seja deletado por engano ou misturado com o código raiz.

### Bibliotecas Principais Utilizadas
- `python-crontab`: Para interagir com o agendador nativo do sistema Unix/Mac.
- `CustomTkinter`: Interface gráfica de usuário moderna, dark-mode native.
- `rumps`: Integração impecável da barra de menus superior do macOS em pouquíssimas linhas de código.

---

<a id="español"></a>
## Español

**CronBuddy** es un gestor moderno y nativo de `cron jobs` para macOS, construido completamente en Python. A diferencia de las soluciones tradicionales de terminal, CronBuddy ofrece una interfaz gráfica minimalista (con soporte para Dark Mode nativo), integración directa en la barra de menús (Menu Bar) de Mac, y un administrador de archivos incorporado para manejar fácilmente registros, scripts y plantillas de comandos.

### Funcionalidades

- **Gestor Visual de Cron:** Visualiza todas tus tareas programadas activas e inactivas en tarjetas modernas y elegantes.
- **Icono en la Barra de Menús (Menu Bar):** La aplicación se ejecuta silenciosamente en la parte superior de tu pantalla, utilizando la biblioteca `rumps` enfocada en el ecosistema de Apple.
- **Programación Intuitiva:** En lugar de intentar recordar la sintaxis de cron (`* * * * *`), la interfaz ofrece cuadros de selección como "Every Day at Midnight", que traducen tu voluntad a código automáticamente.
- **Plantillas Dinámicas:** La carpeta `templates/` en el proyecto sirve como una galería de opciones de comandos útiles (ej: Limpiar la papelera, Ping, Verificar registros de CPU). Agrega tus scripts allí y la interfaz absorberá la plantilla al instante.
- **Administrador de Archivos Multi-Pestaña:** Con solo un clic, visualiza, crea, elimina y edita scripts creados por ti en tu carpeta local. Incluye pestañas exclusivas para:
  - Scripts en Shell (`~/CronBuddyScripts/shell`)
  - Scripts en Python (`~/CronBuddyScripts/python`)
  - Registros de Ejecución (`~/CronBuddyScripts/logs`)
  - Tus Plantillas Personalizadas (`/templates`)
- **Iniciar con macOS (Autostart):** Activa o desactiva el inicio automático de CronBuddy al iniciar sesión en el sistema directamente a través de una moderna casilla de verificación en la barra lateral.

### Requisitos Previos e Instalación

1. Asegúrate de tener Python 3 instalado en tu macOS. Se recomienda utilizar un entorno virtual (`venv`).
2. Si Python se queja de la falta del paquete de interfaz (`_tkinter` missing), asegúrate de instalarlo a través de Homebrew (ej: `brew install python-tk@3.14`).
3. Clona este repositorio e instala las dependencias:

```bash
git clone https://github.com/lucasrafaldini/cronbuddy.git
cd cronbuddy
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Cómo Ejecutar (Desarrollo)

El flujo de trabajo recomendado para el desarrollo es iniciar la aplicación a través de la terminal:

```bash
python menubar.py
```
*(Aparecerá un icono en la esquina superior derecha de tu Mac).*

### Generando el Ejecutable (.app) para macOS

Si deseas transformar CronBuddy en una aplicación nativa de macOS (sin necesidad de abrir la terminal):

1. Asegúrate de estar dentro del entorno virtual activo.
2. Ejecuta el comando de compilación:

```bash
./build_app.sh
```

La aplicación se generará en la carpeta `dist/CronBuddy.app`. Puedes arrastrarla a tu carpeta de **Aplicaciones** y ejecutarla como cualquier otra aplicación de Mac.

#### Modo de Prueba
Si deseas validar un comando rápidamente, inicia la aplicación con la bandera de prueba:

```bash
python menubar.py --test
```
¡Esta bandera agregará una opción especial **"One Minute From Now (Test)"** al momento de elegir el horario de un Cron Job. Programará el comando para ejecutarse exactamente en el minuto siguiente!

### Estructura de Directorios

CronBuddy organiza los archivos en dos lugares principales:

1. **Repositorio del Proyecto:** Donde vive el código fuente. Aquí también encontrarás la carpeta `templates/` con scripts nativos útiles (`.sh`, `.py`).
2. **Directorio del Usuario (`~/CronBuddyScripts`):** La carpeta en el inicio de tu usuario, con las debidas separaciones (`/shell`, `/python`, `/logs`) utilizada para asegurar que ninguno de tus scripts se elimine por error o se mezcle con el código raíz.

### Principales Bibliotecas Utilizadas
- `python-crontab`: Para interactuar con el programador nativo del sistema Unix/Mac.
- `CustomTkinter`: Interfaz gráfica de usuario moderna y nativa en modo oscuro.
- `rumps`: Integración impecable con la barra de menús superior de macOS en muy pocas líneas de código.
