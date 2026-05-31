# 🛒 Order Service — Microservice Commandes

![Node.js](https://img.shields.io/badge/Node.js-20-339933?logo=nodedotjs&logoColor=white)
![Express](https://img.shields.io/badge/Express-4.x-000000?logo=express&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-7-13aa52?logo=mongodb&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI/CD-2088FF?logo=github&logoColor=white)
![Trivy](https://img.shields.io/badge/Trivy-security_scan-1904DA?logo=aqua&logoColor=white)
![GHCR](https://img.shields.io/badge/GHCR-registry-24292e?logo=github&logoColor=white)

Microservice de gestion des commandes avec authentification JWT — partie de l'architecture microservices e-commerce déployée sur **Kubernetes** (Helm) ou **Docker Swarm** (Kong Gateway).

> 💡 **Objectif Portfolio** : Ce service illustre la gestion d'une ressource métier sensible (commandes financières) avec GitHub Actions CI/CD complet — tests → build Docker → scan Trivy → push GHCR.

---

## 🗺️ Positionnement dans l'Architecture

```
          Frontend (192.168.56.114)
                      │
                      ▼
┌──────────────────────────────────────────────┐
│  Kubernetes Cluster (192.168.56.111)         │
│  Ingress :30080                              │
│  ├── 🔐 auth-service    :3001                │
│  ├── 📦 product-service :3002                │
│  ├── 🛒 order-service   :3003  ← Ce service  │
│  └── ⭐ review-service  :3004                │
└──────────────────────────────────────────────┘
                      │
                      ▼
  MariaDB (192.168.56.115:3306) — ecommerce_db
```

**Rôle de ce service :** Gestion complète du cycle de vie des commandes. Tous les endpoints nécessitent un JWT valide — les utilisateurs ne voient que leurs propres commandes, les admins voient tout.

---

## 📡 Endpoints

| Méthode | Endpoint | Auth | Description |
|---------|----------|:----:|-------------|
| `GET` | `/api/orders` | JWT | Mes commandes (user courant) |
| `POST` | `/api/orders` | JWT | Créer une commande |
| `GET` | `/api/orders/:id` | JWT/Admin | Détails d'une commande |
| `PUT` | `/api/orders/:id/status` | Admin | Changer statut (pending→shipped…) |
| `GET` | `/api/orders/all` | Admin | Toutes les commandes |
| `GET` | `/api/orders/health` | — | Liveness probe |
| `GET` | `/api/orders/metrics` | — | Métriques Prometheus |

**Statuts commande :** `pending` → `processing` → `shipped` → `delivered` / `cancelled`

---

## 🔄 Pipeline CI/CD

```
                    GitHub Push / Pull Request
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│  Job 1 : Test API (parallèle)                          │
│  └── npm install + test-api.sh : 10-13 tests endpoints  │
│  └── Dépendance : MongoDB 7                             │
├─────────────────────────────────────────────────────────┤
│  Job 2 : Dependency Scanning (parallèle)                │
│  └── Trivy FS scan : scanne les vulnérabilités          │
├─────────────────────────────────────────────────────────┤
│  Job 3 : Build Docker Image (après tests réussis)      │
│  └── Docker multi-stage : Node 20 Alpine                │
│  └── Sauvegarde l'image en artefact                     │
├─────────────────────────────────────────────────────────┤
│  Job 4 : Scan Container (main uniquement)              │
│  └── Trivy container scan : détecte vulnérabilités      │
├─────────────────────────────────────────────────────────┤
│  Job 5 : Push to GHCR (main uniquement)                │
│  └── GitHub Container Registry : ghcr.io/...           │
│  └── Tags : commit-sha + latest                        │
└─────────────────────────────────────────────────────────┘
```

<details>
  <summary><strong>🦊⚙️ Afficher l'Architecture du Pipeline CI/CD (Gitlab)</strong></summary>

![Pipeline CI/CD](https://gitlab.com/yara_portfolio/devops/ecommerce/ecommerce-frontend/-/raw/main/.img/Pipeline-CICD-GitLab.png)

</details>

**Fichier CI/CD :**
- `.github/workflows/ci.yml` — Pipeline GitHub Actions complète avec tests, scans de sécurité et déploiement

---

## ⚡ Quick Start

```bash
git clone https://gitlab.com/yara_portfolio/devops/ecommerce/microservice/order-service.git
cd order-service
cp .env.example .env && nano .env

npm install && npm start
# ✅ http://localhost:3003/api/orders/health
```

---

## ⚙️ Variables d'Environnement

| Variable | Description | Valeur | Requis |
|----------|-------------|--------|--------|
| `PORT` | Port du service | `3003` | ✅ |
| `NODE_ENV` | Environnement | `production` | ❌ |
| `DB_HOST` | IP serveur MariaDB | `192.168.56.115` | ✅ |
| `DB_PORT` | Port MariaDB | `3306` | ✅ |
| `DB_NAME` | Base de données | `ecommerce_db` | ✅ |
| `DB_USER` | Utilisateur BD | `devops_user` | ✅ |
| `DB_PASSWORD` | Mot de passe BD | — | ✅ |
| `JWT_SECRET` | Clé JWT (même que auth-service) | — | ✅ |

> ⚠️ `JWT_SECRET` doit être **identique** à celui utilisé par auth-service pour valider les tokens.

---

## 📁 Structure du Projet

```
order-service/
├── src/
│   ├── config/database.js        # Pool de connexions MariaDB
│   ├── middleware/
│   │   ├── authMiddleware.js     # Vérification JWT + rôle admin
│   │   └── metrics.js            # Collecte métriques Prometheus
│   ├── routes/order.js           # CRUD commandes + changement statut
│   └── server.js
├── testapi/
│   ├── test-api.sh               # Tests intégration (10-13 tests)
│   ├── data-test-api.sql         # Données de test BD
│   ├── security-scan.sh          # Scan CVE Trivy
│   └── git-security-scan.sh      # Détection secrets
├── Dockerfile
├── Jenkinsfile-ci
├── .gitlab-ci.yml
└── .env.example
```

---

## 🚀 Déploiement

### Docker

```bash
docker build -t order-service:v3.2 .

docker run -d \
  --name order-service \
  -p 3003:3003 \
  -e DB_HOST=192.168.56.115 \
  -e DB_PASSWORD=devops_password \
  -e JWT_SECRET=your_secret_min_32_chars \
  order-service:v3.2
```

### Kubernetes (via Helm Chart)

```bash
helm upgrade ecommerce-microservices . \
  --reuse-values \
  --set services.orderService.image.tag=v3.2
```

---

## 🧪 Tests

```bash
# Health
curl http://localhost:3003/api/orders/health

# Login pour obtenir un token
TOKEN=$(curl -s -X POST http://localhost:3001/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"john.doe@example.com","password":"password123"}' \
  | jq -r '.token')

# Mes commandes
curl http://localhost:3003/api/orders \
  -H "Authorization: Bearer $TOKEN"

# Créer une commande
curl -X POST http://localhost:3003/api/orders \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"product_id":1,"quantity":2}],"shipping_address":"123 Rue Test"}'

# Suite complète
cd testapi && bash test-api.sh
```

---

## 🔗 Projets Liés

| Composant | Repository |
|-----------|------------|
| 🔐 Auth Service | [auth-service](https://gitlab.com/yara_portfolio/devops/ecommerce/microservice/auth-service) |
| 📦 Product Service | [product-service](https://gitlab.com/yara_portfolio/devops/ecommerce/microservice/product-service) |
| ⭐ Review Service | [review-service](https://gitlab.com/yara_portfolio/devops/ecommerce/microservice/review-service) |
| ⎈ Helm Chart | [k8s-helm-chart](https://gitlab.com/yara_portfolio/devops/ecommerce/devops-tools/k8s-helm-chart) |
| 🗄️ Base de données | [ecommerce-database](https://gitlab.com/yara_portfolio/devops/ecommerce/ecommerce-database) |

---

## 👨‍💻 Auteur

**Yara Mahi Mohamed** — Portfolio DevOps & SRE

*⭐ N'oubliez pas de star ce repo si vous le trouvez utile !*
