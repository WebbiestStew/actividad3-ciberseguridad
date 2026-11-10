# Actividad 3 · Ciberseguridad

Laboratorio local de infraestructura como código, seguridad de imágenes de contenedor y control de acceso en una API. Ejecuta los comandos desde la raíz del proyecto.

## Fase 1 · Bucket S3 con Terraform y LocalStack

En macOS instala [Docker Desktop](https://docs.docker.com/desktop/setup/install/mac-install/) para tu arquitectura. Requiere un Mac compatible con virtualización y Docker Desktop abierto. Instala también [Terraform](https://developer.hashicorp.com/terraform/install), [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) y Python 3.

1. Selecciona el plan **Hobby** en [LocalStack for AWS](https://www.localstack.cloud/pricing) y guarda una captura del plan sin datos de cuenta. Copia `.env.example` a `.env` y completa `LOCALSTACK_AUTH_TOKEN` en un editor local. El archivo está excluido de Git.
2. Comprueba las herramientas y que el puerto 4566 esté libre. En macOS, `lsof` sin salida indica que no encontró un proceso escuchando en ese puerto.

   ```sh
   docker --version
   docker compose version
   terraform version
   aws --version
   docker ps
   lsof -nP -iTCP:4566 -sTCP:LISTEN
   ```

3. Levanta LocalStack y captura el estado saludable. Compose publica S3 únicamente en la interfaz de loopback.

   ```sh
   docker compose up -d --wait
   docker compose ps
   curl -fsS http://localhost:4566/_localstack/health
   ```

4. Inicializa, valida y revisa el plan. En un laboratorio nuevo deben aparecer tres altas: bucket, cifrado AES256 y bloqueo de acceso público. Aplica el plan revisado.

   ```sh
   terraform init
   terraform validate
   terraform plan -out=actividad3.tfplan
   terraform show -no-color actividad3.tfplan
   terraform apply actividad3.tfplan
   ```

5. Ejecuta `bash scripts/verify-s3.sh` y guarda la salida. El script consulta el cifrado y los cuatro controles, carga `prueba.txt`, lista objetos, intenta descargar sin firma y consulta el estado de la política.
6. En el [Resource Browser de LocalStack](https://docs.localstack.cloud/aws/connecting/localstack-console/resource-browser/), desde el mismo Mac, selecciona el endpoint `http://localhost:4566`, abre S3 y captura el bucket `actividad3-seguro-local` con el objeto de prueba.

Terraform declara la configuración deseada. Las consultas de AWS CLI comprueban lo que el simulador devuelve. La descarga sin firma mide el comportamiento observado, que depende de la cobertura de autorización de LocalStack. `NoSuchBucketPolicy` indica que el bucket carece de una política adjunta. La exposición se evalúa con los controles aplicados y el resultado de la prueba anónima.

## Fase 2 · Escaneo de imágenes Node

Los dos Dockerfiles conservan el punto de partida y la actualización solicitada. Si Docker está disponible, puedes compilar ambas variantes con la misma arquitectura:

```sh
docker build --platform linux/amd64 -f containers/Dockerfile.node14 -t actividad3:node14 containers
docker build --platform linux/amd64 -f containers/Dockerfile.node18 -t actividad3:node18 containers
```

Instala [Trivy](https://trivy.dev/docs/latest/getting-started/installation/) y ejecuta `bash scripts/scan-images.sh`. El script escanea las dos imágenes base de Docker Hub para `linux/amd64`, genera informes JSON y compara los totales por severidad. Los resultados dependen del digest de la imagen y de la base de datos de vulnerabilidades. Las ramas Node 14 y 18 ya terminaron su ciclo de soporte. [Ciclo de soporte de Node.js](https://nodejs.org/en/about/eol)

## Fase 3 · JWT y OWASP ZAP

Instala Node.js 22 o posterior, [ZAP](https://www.zaproxy.org/download/) y el Java que requiera tu distribución de ZAP.

```sh
npm --prefix api ci
npm --prefix api test
ZAP_SH=/ruta/a/zap.sh bash scripts/scan-api.sh
```

El script inicia la API y el proxy de ZAP en loopback. Envía cuatro solicitudes a través de ZAP y comprueba los códigos `401`, `401`, `403` y `200` para token ausente, inválido, rol de usuario y rol de administrador, respectivamente. Ejecuta el escaneo activo de `/health` y `/api/admin` y guarda el resumen y el informe HTML en `evidence/`. Los tokens de prueba caducan en cinco minutos.

La API valida firma HS256, emisor, audiencia, expiración y sujeto. Solo el rol `admin` puede acceder a `/api/admin`. El generador de tokens se ejecuta por terminal y requiere el secreto del laboratorio. Para explorar la API manualmente, exporta `JWT_SECRET="$(openssl rand -hex 32)"`, inicia `npm --prefix api start` y consulta `http://127.0.0.1:3000/openapi.json`.
