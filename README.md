# Powerlog

**Powerlog** es una aplicación móvil diseñada para atletas de powerlifting que buscan llevar un registro detallado de sus entrenamientos. La app permite gestionar sesiones de entrenamiento, registrar ejercicios, y realizar un seguimiento del progreso de manera eficiente y organizada.

## Características Principales

- **Generación de bloques de entrenamiento**: Crea y organiza bloques personalizados para tus ciclos de entrenamiento.
- **Registro de sesiones con cronómetro**: Lleva un control preciso del tiempo de descanso entre series y ejercicios.
- **Selección de ejercicios desde base de datos**: Accede a una lista de ejercicios predefinidos o personaliza los tuyos.
- **Sistema de variantes por etiquetas**: Clasifica y organiza ejercicios mediante etiquetas para una búsqueda más rápida.
- **Sincronización con Supabase**: Almacena y recupera datos de manera segura en la nube.
- **Validación de datos**: Asegura que los datos ingresados sean correctos y consistentes.
- **Notificaciones al finalizar descansos**: Recibe alertas cuando el temporizador de descanso termina.
- **Interfaz intuitiva**: Diseñada para facilitar la navegación y el uso diario.

## Stack Tecnológico

- **Flutter**: Framework principal para el desarrollo de la interfaz de usuario.
- **Dart**: Lenguaje de programación utilizado en la aplicación.
- **Supabase**: Backend para la gestión de datos en tiempo real.
- **SQLite**: Base de datos local para almacenamiento offline.
- **Provider/Riverpod**: Gestión del estado de la aplicación.
- **Gradle**: Herramienta de construcción para la integración con Android.
- **Kotlin y Java**: Compatibilidad con el ecosistema de Android.
- **C++**: Uso en componentes nativos específicos.

## Estructura del Proyecto

El proyecto está organizado en las siguientes carpetas principales:

- **`screens`**: Contiene las pantallas principales de la aplicación, como el registro de sesiones, la selección de ejercicios y la configuración de bloques.
- **`widgets`**: Incluye componentes reutilizables de la interfaz de usuario, como botones personalizados, temporizadores y listas.
- **`utils`**: Funciones y utilidades auxiliares, como validaciones, formateo de datos y manejo de errores.
- **`models`**: Define las clases y estructuras de datos utilizadas en la aplicación, como ejercicios, sesiones y bloques de entrenamiento.

## Contribuciones

Si deseas contribuir al desarrollo de **Powerlog**, por favor abre un issue o envía un pull request. ¡Toda ayuda es bienvenida!

## Licencia

Este proyecto está bajo la licencia [MIT](LICENSE).