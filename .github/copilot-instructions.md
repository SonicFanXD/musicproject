\# Instrucciones para GitHub Copilot Coding Agent — Aurora Player



\## Reglas de Oro

1\. \*\*Un commit = un cambio lógico.\*\* Nunca agrupes múltiples fixes.

2\. \*\*No declares una tarea como "terminada" hasta que el CI esté en VERDE.\*\*

3\. \*\*Antes de tocar un archivo, LÉELO.\*\* Los archivos pueden haber cambiado.

4\. \*\*Balance de llaves obligatorio.\*\* Antes de pushear, verifica con:

&#x20;  `awk '{o+=gsub(/{/,"{"); c+=gsub(/}/,"}")} END{print "abre:",o,"cierra:",c,"diff:",o-c}' <archivo>`

&#x20;  Debe dar `diff: 0`.

5\. \*\*Si dudas sobre impacto visual o auditivo, PREGUNTA.\*\*



\## Jerarquía de Prioridades (INVIOLABLE)

1\. \*\*ESTABILIDAD\*\* (compilar, no crashear)

2\. \*\*CALIDAD VISUAL\*\* (materiales, gradientes, blur intactos)

3\. \*\*CALIDAD AUDITIVA\*\* (bit-perfect cuando sea posible)

4\. \*\*RENDIMIENTO\*\* (60 fps como consecuencia)

5\. \*\*BATERÍA\*\* (nunca a costa de 1-4)



\## Entorno

\- Windows + GitHub Actions (no hay Xcode local).

\- Runner: `macos-26-arm64` con Xcode 26.6.

\- Target: iOS 16.0 mínimo.



\## Prohibiciones

\- NO usar `AnyView`.

\- NO convertir structs en clases.

\- NO cambiar `.ultraThinMaterial` por colores opacos.

\- NO reducir resolución de artwork de portada grande.

\- NO tocar `Info.plist` ni `LaunchScreen.storyboard`.

\- NO ejecutar migraciones de UserDefaults.

\- NO cambiar keys de `@AppStorage`.

\- NO tocar features no relacionadas.



\## Lo que SÍ es legítimo

\- Pre-calcular blurs UNA vez en background.

\- Cachear thumbnails (misma resolución mostrada).

\- Cancelar animations/timers en background.

\- Saltar trabajo cuando un valor no cambió.

\- Aumentar concurrencia de lecturas de I/O.



\## Type-checking del compilador Swift

\- Máximo 5-6 modificadores encadenados por expresión en body.

\- Closures largas (`.sheet { }`, `.toolbar { }`) van aisladas en sus propios @ViewBuilder.

\- Si un body tarda >500ms en type-checkear, dividirlo en getters encadenados.

\- Si el compilador dice "unable to type-check this expression in reasonable time", extraer sub-expresiones. NUNCA usar AnyView.



\## Formato de Reporte al Terminar

Cambios aplicados, Verificación (balance de llaves + greps), Estado CI (verde/rojo), Pendiente de validación humana.

