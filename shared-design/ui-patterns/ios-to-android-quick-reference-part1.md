# 🚀 Referencia Rápida: iOS → Android (Parte 1: UI y Layout)

Guía rápida para convertir componentes de SwiftUI a Android (Kotlin/XML).

## 📱 Componentes de UI

### Navigation

| SwiftUI | Android (Kotlin) |
|---------|------------------|
| `NavigationStack` | `NavHostFragment` + Navigation Component |
| `NavigationLink(destination:)` | `findNavController().navigate(R.id.action)` |
| `sheet(isPresented:)` | `BottomSheetDialogFragment` |
| `fullScreenCover` | `Activity` con fullscreen theme |

### Layout

| SwiftUI | Android |
|---------|---------|
| `VStack` | `LinearLayout(orientation=vertical)` |
| `HStack` | `LinearLayout(orientation=horizontal)` |
| `ZStack` | `FrameLayout` |
| `List` | `RecyclerView` |
| `ScrollView` | `ScrollView` / `NestedScrollView` |
| `LazyVStack` | `RecyclerView` con `LinearLayoutManager` |
| `Grid` | `RecyclerView` con `GridLayoutManager` |

### Controles

| SwiftUI | Android |
|---------|---------|
| `Button` | `Button` / `MaterialButton` |
| `Toggle` | `Switch` / `SwitchMaterial` |
| `Slider` | `SeekBar` / `Slider` (Material) |
| `TextField` | `EditText` / `TextInputEditText` |
| `Picker` | `Spinner` / `BottomSheet` con opciones |
| `Menu` | `PopupMenu` / `BottomSheetMenu` |

## 🎨 Estilos y Temas

### Colores Dinámicos

**iOS (Swift):**
```swift
@Published var accentColor: Color = AppTheme.accent
```

**Android (Kotlin):**
```kotlin
val accentColor = MutableLiveData<Int>().apply {
    value = ThemeManager.getInstance(context).getCurrentAccentColor()
}
```

### Glassmorphism Effect

**iOS (Swift):**
```swift
.background(.ultraThinMaterial)
```

**Android (XML):**
```xml
<!-- res/drawable/glass_background.xml -->
<shape android:shape="rectangle">
    <solid android:color="#14FFFFFF" /> <!-- 8% white -->
    <corners android:radius="16dp" />
</shape>
```

### Sombras

**iOS (Swift):**
```swift
.shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 15)
```

**Android (XML):**
```xml
<!-- Usar elevation para sombras -->
<androidx.cardview.widget.CardView
    android:elevation="8dp"
    app:cardCornerRadius="16dp" />
```

## 🔄 Estado y Data Binding

### ObservableObject → ViewModel

**iOS (Swift):**
```swift
class AudioEngine: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
}
```

**Android (Kotlin):**
```kotlin
class PlayerViewModel : ViewModel() {
    val isPlaying = MutableLiveData(false)
    val currentTime = MutableLiveData(0.0)
}
```

### @State → rememberSaveable

**iOS (Swift):**
```swift
@State private var searchText = ""
```

**Android (Kotlin):**
```kotlin
var searchText by rememberSaveable { mutableStateOf("") }
```

### @AppStorage → SharedPreferences

**iOS (Swift):**
```swift
@AppStorage("com.aurora.showVisualizer") private var showVisualizer = true
```

**Android (Kotlin):**
```kotlin
val prefs = context.getSharedPreferences("aurora_prefs", Context.MODE_PRIVATE)
var showVisualizer = prefs.getBoolean("show_visualizer", true)
```

**Continúa en Parte 2: Audio y Animaciones** →