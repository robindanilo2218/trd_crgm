# Reglas e Instrucciones para Agentes de IA

Este archivo contiene reglas específicas para que los asistentes de inteligencia artificial sepan cómo interactuar con este proyecto.

## Control de Versiones (Git)

1. **Commits y Subidas:**
   - El agente es libre de modificar archivos, usar `git add` y crear `git commit` con mensajes descriptivos.
   - **IMPORTANTE PARA `git push`:** El proyecto usa una URL HTTPS de GitHub que requiere un Personal Access Token (PAT). Si el agente intenta hacer un `git push` de forma automática, podría quedarse colgado esperando las credenciales en segundo plano.
   - La regla es: El agente debe preparar el commit y, si no tiene la certeza de contar con credenciales válidas en el entorno, **debe pedirle al usuario que ejecute `git push` manualmente** en su propia terminal.

## Proyecto (PWA y Web)
- El repositorio (`trd_crgm`) funciona principalmente con archivos estáticos (`index.html`, `sw.js`, `manifest.json`).
- Asegurarse de mantener las rutas y las configuraciones del Service Worker (PWA) correctamente actualizadas.
