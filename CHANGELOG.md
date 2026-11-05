# Changelog

All notable changes to this project will be documented in this file.

<p align="center">
  <a href="#english">English</a> | 
  <a href="#português">Português</a> | 
  <a href="#español">Español</a>
</p>

---

<a id="english"></a>
## [2.0.0] - Native rewrite

CronBuddy is now a native Swift and SwiftUI app. The Python implementation is retired.

### Added
- **Rich menu bar**: upcoming runs, each job's last result, run and pause from the menu, optional countdown to the next run.
- **New kinds of action**: script files (shell, Python, Ruby, AppleScript, JXA, Automator workflows), inline AppleScript and Shortcuts, alongside shell commands.
- **launchd scheduling** (now the default) next to cron, with plain-language schedules: intervals, several times a day, weekdays, days of the month, at login, or raw cron. The editor previews the next runs.
- **Test Run** in the editor with live output, and **Run Now** with live output on every job.
- **Run history**: output, exit code and duration for every run, log search, per-job success rate, and an *Activity* view across all jobs.
- **Notifications** on failure, or on success with an output preview.
- **Twenty templates**, many ported from Khronos, plus **Import from crontab**.
- **Themes**: System, Thoth, Paper, Phosphor and Nord.
- Every job runs through CronBuddy's own executable, so one Full Disk Access grant covers them all. Lines written by 1.x (`--run … --name …`) keep working and can be imported.

### Removed
- The Python app, its `~/CronBuddyScripts` file manager and the `templates/` folder.
## [1.0.0] - v1.0.0 Release

### Added
- **Premium Branding & Icons**: Integrated brand new custom logo (`cronbuddy.png`) and slogan graphics. Compiled official macOS app icons (`app_icon.icns`) and dark/light dynamic status bar menu template icons (`status_icon_template.png`).
- **Autostart Support**: Added a native "Start with macOS" sidebar checkbox utilizing macOS user LaunchAgents plist files.
- **Immediate Execution ("Run Now")**: Integrated a green premium **"▶ Run Now"** button in each job card to test cron jobs instantly in background subprocesses without locking the GUI.
- **Editable Comments**: Enabled full modification of comment descriptions for active cron jobs directly inside `JobDialog` and updated macOS crontab dynamically.
- **Responsive Layout Redesign**: Re-engineered cron cards by moving the action buttons (Delete, Edit, Pause, Run Now) to a responsive actions row below the command panel.
- **Python Template Support**: Extended `TemplateManager` to recursively scan subdirectories and detect `.py` files to automatically schedule cron tasks using the `/usr/bin/python3` interpreter.
- **Bilingual & Trilingual Polish**: Complete internationalization support with the main project `README.md` and this `CHANGELOG.md` fully available in English, Portuguese, and Spanish.
- **Prepopulated Templates**: Provided 9 ready-to-use, practical, macOS-optimized shell templates for system tasks (trash cleaning, backups, hardware usage logs, voice announcements, etc.).

---

<a id="português"></a>
## [2.0.0] - Reescrita nativa

O CronBuddy agora é um app nativo em Swift e SwiftUI. A implementação em Python foi aposentada.

### Adicionado
- **Barra de menus completa**: próximas execuções, último resultado de cada job, rodar e pausar pelo menu, contagem regressiva opcional.
- **Novos tipos de ação**: arquivos de script (shell, Python, Ruby, AppleScript, JXA, fluxos do Automator), AppleScript inline e Atalhos, além de comandos de shell.
- **Agendamento via launchd** (agora o padrão) ao lado do cron, com agendamentos em linguagem natural e prévia das próximas execuções.
- **Test Run** no editor e **Run Now** em cada job, com saída ao vivo.
- **Histórico**: saída, código de saída e duração de cada execução, busca nos logs, taxa de sucesso e a tela *Activity*.
- **Notificações** de falha, ou de sucesso com prévia da saída.
- **Vinte templates**, muitos vindos do Khronos, e **Import from crontab**.
- **Temas**: Sistema, Thoth, Paper, Phosphor e Nord.
- Todo job roda pelo executável do CronBuddy, então uma única permissão de Acesso Total ao Disco vale para todos. Linhas criadas pela 1.x (`--run … --name …`) continuam funcionando e podem ser importadas.

### Removido
- O app em Python, o gerenciador de arquivos de `~/CronBuddyScripts` e a pasta `templates/`.
## [1.0.0] - Lançamento da v1.0.0

### Adicionado
- **Branding & Ícones Premium**: Integração do novo logotipo oficial (`cronbuddy.png`) e slogan gráfico. Compilação do pacote oficial de ícones nativos do macOS (`app_icon.icns`) e ícones de silhueta dinâmicos claro/escuro para a barra de status (`status_icon_template.png`).
- **Iniciar com o macOS**: Adição de uma caixa de seleção na barra lateral para habilitar ou desabilitar o autostart no login do sistema utilizando LaunchAgents plist nativos do macOS.
- **Execução Instantânea ("▶ Run Now")**: Adição de um botão verde premium em cada card para testar comandos na hora, executando assincronamente em segundo plano sem travar a interface gráfica.
- **Edição Completa de Descrições**: Liberação da edição do campo "Description (Comment/ID)" para cron jobs ativos na tela `JobDialog` salvando as mudanças em tempo real na crontab do macOS.
- **Design Responsivo Otimizado**: Reposicionamento do painel de botões de ação (Delete, Edit, Pause, Run Now) para a parte inferior de cada card de cron job, impedindo cortes em janelas pequenas.
- **Suporte a Templates Python**: Atualização do `TemplateManager` para varredura recursiva de diretórios e agendamento automático de arquivos `.py` chamando o interpretador nativo `/usr/bin/python3`.
- **Internacionalização Trilíngue**: Documentações do projeto `README.md` e `CHANGELOG.md` completamente redigidas em Inglês, Português e Espanhol com menu interativo.
- **Templates Úteis Preenchidos**: Criação de 9 scripts de templates em shell (.sh) prontos para uso no macOS (limpeza de lixeira, backups, logs de hardware, avisos por voz sintetizada, etc.).

---

<a id="español"></a>
## [2.0.0] - Reescritura nativa

CronBuddy ahora es una app nativa en Swift y SwiftUI. La implementación en Python queda retirada.

### Añadido
- **Barra de menús completa**, nuevos tipos de acción (scripts, AppleScript, Automator, Atajos), programación con **launchd** (por defecto) o cron, **Test Run** y **Run Now** con salida en vivo, historial con búsqueda, notificaciones, veinte plantillas, **Import from crontab** y cinco temas.
- Cada job se ejecuta a través del ejecutable de CronBuddy, así que un único permiso de Acceso Total al Disco los cubre todos. Las líneas de la 1.x (`--run … --name …`) siguen funcionando y pueden importarse.

### Eliminado
- La app en Python, el gestor de archivos de `~/CronBuddyScripts` y la carpeta `templates/`.
## [1.0.0] - Lanzamiento de v1.0.0

### Añadido
- **Branding e Iconos Premium**: Integración del nuevo logotipo oficial (`cronbuddy.png`) y slogan gráfico del proyecto. Compilación del paquete de iconos nativos de macOS (`app_icon.icns`) e iconos de silueta dinámicos claro/oscuro para la barra de estado (`status_icon_template.png`).
- **Inicio con macOS (Autostart)**: Se agregó una casilla de verificación en la barra lateral para activar/desactivar el autostart en el inicio de sesión del sistema mediante archivos LaunchAgents plist nativos de macOS.
- **Ejecución Instantánea ("▶ Run Now")**: Botón verde premium en cada tarjeta para probar comandos al instante de forma asíncrona en segundo plano sin congelar la interfaz de usuario.
- **Edición de Descripciones**: Posibilidad de modificar la descripción/comentario de cron jobs activos dentro de la pantalla `JobDialog` actualizando la crontab de macOS dinámicamente.
- **Diseño Responsivo Optimizado**: Rediseño de las tarjetas moviendo los botones de acción (Delete, Edit, Pause, Run Now) a una fila inferior responsiva, evitando que se corten en pantallas pequeñas.
- **Soporte para Plantillas Python**: Actualización de `TemplateManager` para buscar recursivamente en subcarpetas y programar automáticamente archivos `.py` invocando el intérprete `/usr/bin/python3`.
- **Internacionalización Trilingüe**: Documentación de `README.md` y este `CHANGELOG.md` completamente escritos y estructurados en Inglés, Portugués y Español con menús interactivos.
- **Plantillas Útiles Listas**: Se proporcionaron 9 scripts de plantillas listos para usar en macOS (limpieza de papelera, copias de seguridad, logs de hardware, anuncios por voz sintetizada, etc.).
