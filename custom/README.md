# VendeEnOne Custom Extensions

Este directorio contiene todas las personalizaciones de VendeEnOne sobre Chatwoot.

## Estructura

```
custom/
├── app/
│   ├── models/custom/       # Extensiones de modelos
│   ├── controllers/custom/  # Extensiones de controladores
│   └── views/               # Vistas custom (overrides parciales)
├── lib/custom/              # Librerías y servicios custom
└── config/
    └── initializers/        # Inicializadores custom
```

## Cómo funciona

1. El archivo `config/application.rb` carga los paths de `custom/` si el directorio existe
2. `lib/chatwoot_app.rb` detecta `custom/` y lo incluye en `ChatwootApp.extensions`
3. Los métodos `prepend_mod_with` y `include_mod_with` buscan módulos en `Custom::`

## Reglas

- **NO modificar archivos fuera de `custom/`** — TODO el código custom va aquí
- Nombrar módulos como `Custom::NombreDelModelo` (namespace `Custom`)
- Usar `super` para llamar al método original del core cuando sobreescribas
- Para extensiones que no son overrides (métodos nuevos), definir en `Custom::`

## Ejemplo

```ruby
# custom/app/models/custom/account.rb
module Custom::Account
  def my_custom_method
    # lógica custom
  end
end
```

Y en el core:
```ruby
# app/models/account.rb
Account.prepend_mod_with('Account')
```
