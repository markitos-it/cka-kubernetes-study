# Kubernetes CKA Preparation and Automation Laboratorie

Este repositorio centraliza scripts de automatización, guías de arquitectura y laboratorios prácticos orientados a dominar los objetivos del examen Certified Kubernetes Administrator. El enfoque principal es sustituir las tareas operativas manuales y repetitivas por herramientas de automatización en Bash y configuraciones reproducibles en entornos locales de ingeniería.

---

## Estructura del Repositorio y Componentes Core

El repositorio se organiza de forma modular para abordar los pilares fundamentales de la administración y la seguridad en clusters de Kubernetes:

* **`/certs`**: Directorio local autogenerado destinado a almacenar los artefactos de seguridad criptográfica individuales (Claves privadas `.pem` y Certificados X.509 públicos).
* **`create_k8s_user.sh`**: Script de automatización en Bash que gestiona de extremo a extremo el ciclo de vida de los certificados de cliente (CSR) y audita la seguridad RBAC asignada en el clúster.

---

## Automatización de la Gestión de Identidades en Kubernetes

Uno de los mayores desafíos en la administración de Kubernetes es que **el clúster no cuenta con un objeto o base de datos nativa para gestionar usuarios**. Toda la autenticación de clientes externos se delega en mecanismos como Certificados Digitales X.509.

Para resolver la fricción operativa de firmar claves manualmente, este repositorio incluye un motor de automatización que interactúa de forma nativa con la API `CertificateSigningRequest` de Kubernetes.

### Mecanismo de Autenticación de Usuarios y Grupos

Cuando el componente `kube-apiserver` valida un certificado de cliente, mapea los campos de la estructura del certificado X.509 de la siguiente manera:

* **`CN` (Common Name):** Es interpretado de forma unívoca como el **Username** del operador dentro del clúster.
* **`O` (Organization):** Es interpretado como el **Group** o conjunto de grupos de seguridad a los que pertenece el usuario.

El script automatiza la inyección de múltiples tags `/O=` para permitir que un usuario pertenezca a varios equipos de ingeniería de forma simultánea.

---

## Flujo de Trabajo Operativo del Script de Certificados

El script `create_k8s_user.sh` implementa una arquitectura secuencial dividida en fases estrictas para garantizar la resiliencia en la creación de las credenciales:

### Fase 1: Validación de Nomenclatura Estricta

Se aplica una expresión regular que valida que el nombre de usuario cumpla con los estándares de DNS de Kubernetes:

* Debe comenzar obligatoriamente con una letra minúscula.
* Solo se permiten minúsculas, números y guiones medios.
* La longitud permitida es de 3 a 20 caracteres.

### Fase 2: Generación Criptográfica y Formateo

Se genera una clave privada RSA de 2048 bits de forma local. Posteriormente, se genera el archivo de solicitud de firma (CSR) traduciendo la lista de grupos separados por comas ingresada por el administrador en la estructura nativa requerida por OpenSSL (por ejemplo: `developers,admins` se procesa como `/O=developers/O=admins`).

### Fase 3: Interacción con el API Server

El script genera un manifiesto dinámico de Kubernetes bajo la API `certificates.k8s.io/v1`, codifica el CSR en formato Base64 sin saltos de línea y lo envía al clúster utilizando el firmante estándar `kubernetes.io/kube-apiserver-client`. El certificado resultante tiene una validez estricta de un año (31,536,000 segundos).

### Fase 4: Aprobación y Auditoría Post-Emisión

Se invoca de forma segura `kubectl certificate approve`. Una vez emitido el certificado por la CA del clúster, el script utiliza filtros avanzados de JSONPath y la herramienta `jq` para inspeccionar el clúster en tiempo real, listando de forma automática todos los `RoleBindings` y `ClusterRoleBindings` que ya afectan a esa nueva identidad.

---

## Guía de Uso del Laboratorio

### Requisitos Previos

Para ejecutar los laboratorios de este repositorio, asegúrate de contar con las siguientes herramientas instaladas en tu máquina local o servidor de administración:

* `kubectl` configurado con acceso de Administrador al clúster (`cluster-admin`).
* `openssl` para la generación de los pares de claves.
* `jq` para habilitar el motor de auditoría automática de RBAC.

### Ejecución de Comandos

Para crear un usuario básico con el grupo de autenticación por defecto:

```bash
./create_k8s_user.sh john

```

Para crear un ingeniero de plataforma asociado a múltiples grupos de seguridad personalizados:

```bash
./create_k8s_user.sh markitos developers,admins,viewers

```

### Configuración del Entorno de Trabajo del Cliente (Kubeconfig)

Una vez finalizado el script, puedes registrar las nuevas credenciales criptográficas dentro de tu archivo de configuración de contextos siguiendo los pasos de la salida:

```bash
# 1. Registrar las credenciales criptográficas locales en tu kubeconfig
kubectl config set-credentials markitos \
  --client-certificate=certs/markitos-cert.pem \
  --client-key=certs/markitos-key.pem

# 2. Enlazar el usuario con tu clúster actual en un nuevo contexto lógico
kubectl config set-context markitos-context \
  --cluster=<tu-cluster-name> \
  --user=markitos

# 3. Conmutar tu espacio de trabajo al nuevo contexto seguro
kubectl config use-context markitos-context

```

---

## Profundización en Conceptos de Examen CKA

Para dominar el área de **Seguridad y RBAC** del examen CKA, este laboratorio te permite experimentar de forma directa con los siguientes conceptos teóricos fundamentales:

### Role vs ClusterRole

Los `Roles` definen permisos sobre recursos de Kubernetes (verbos como `get`, `list`, `create`, `watch`) limitados estrictamente al ámbito de un **Namespace** específico. Por el contrario, los `ClusterRoles` se definen a nivel global del clúster, permitiendo auditar recursos no vinculados a namespaces (como `Nodes`, `PersistentVolumes`) o aplicar políticas homogéneas sobre todos los namespaces a la vez.

### RoleBinding vs ClusterRoleBinding

Son los objetos encargados de "unir" los permisos declarados en un Rol con un sujeto (un `User`, un `Group` o una `ServiceAccount`).

* Si unes un `ClusterRole` usando un `RoleBinding` tradicional, el usuario solo tendrá los accesos permitidos **dentro del namespace donde creaste el RoleBinding**.
* Si unes un `ClusterRole` mediante un `ClusterRoleBinding`, el usuario adquirirá los permisos de forma irrestricta en **toda la infraestructura del clúster**.
