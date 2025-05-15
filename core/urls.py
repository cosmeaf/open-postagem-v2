from django.contrib import admin
from django.urls import path
from django.shortcuts import redirect
from rest_framework import permissions
from drf_yasg.views import get_schema_view
from drf_yasg import openapi

# Configuração do schema Swagger/OpenAPI
schema_view = get_schema_view(
    openapi.Info(
        title="Minha API",
        default_version='v1',
        description="Documentação interativa da API",
    ),
    public=True,
    permission_classes=(permissions.AllowAny,),
)

# Rotas principais da API
urlpatterns = [
    path('admin/', admin.site.urls),

    # Swagger UI
    path('swagger/', schema_view.with_ui('swagger', cache_timeout=0), name='schema-swagger-ui'),

    # ReDoc UI
    path('redoc/', schema_view.with_ui('redoc', cache_timeout=0), name='schema-redoc'),

    # Redirecionamento da raiz para o Swagger
    path('', lambda request: redirect('schema-swagger-ui')),
]
