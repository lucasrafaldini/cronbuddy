# Changelog

All notable changes to this project will be documented in this file.

<p align="center">
  <a href="#english">English</a> | 
  <a href="#português">Português</a> | 
  <a href="#español">Español</a>
</p>

---

<a id="english"></a>
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
