# Provence Courses - Base de Données Supabase

> Application de gestion de tournées de livraison pour laboratoires dentaires

**Export complet de la structure de base de données Supabase Cloud**

---

## Table des matières

1. [Schémas visuels](#schémas-visuels) ⭐
2. [Vue d'ensemble](#vue-densemble)
3. [Structure du repository](#structure-du-repository)
4. [Installation locale](#installation-locale)
5. [Architecture de la base de données](#architecture-de-la-base-de-données)
6. [Schéma détaillé des tables](#schéma-détaillé-des-tables)
7. [Relations et clés étrangères](#relations-et-clés-étrangères)
8. [Fonctions stockées PostgreSQL](#fonctions-stockées-postgresql)
9. [Edge Functions (Deno)](#edge-functions-deno)
10. [Storage et buckets](#storage-et-buckets)
11. [Configuration Realtime](#configuration-realtime)
12. [Types TypeScript](#types-typescript)
13. [Workflow métier](#workflow-métier)
14. [Notes de sécurité](#notes-de-sécurité)

---

## Schémas visuels

### Diagramme Entité-Relation (ERD)

```mermaid
erDiagram
    %% Authentification
    AUTH_USERS ||--o| ADMINISTRATORS : "user_id"
    AUTH_USERS ||--o| ADMINS : "user_id"
    AUTH_USERS ||--|| LABORATORIES : "user_id"
    AUTH_USERS ||--|| DRIVERS : "user_id"

    %% Entités principales
    LABORATORIES ||--|| LOCATIONS : "location_id"
    LABORATORIES ||--o{ LABORATORY_CLIENTS : "laboratory_id"
    LABORATORIES ||--o{ LAB_TOURS : "laboratory_id"
    LABORATORIES ||--o{ BILLING_INVOICES : "laboratory_id"

    DRIVERS ||--o{ LABORATORY_CLIENTS : "driver_id"
    DRIVERS ||--o{ DRIVER_ROUTES : "driver_id"
    DRIVERS ||--o{ DRIVER_STATISTICS : "driver_id"

    LABORATORY_CLIENTS ||--|| LOCATIONS : "location_id"
    LABORATORY_CLIENTS ||--o{ LAB_TOUR_STOPS : "client_id"
    LABORATORY_CLIENTS ||--o{ BILLING_CONFIGURATIONS : "client_id"

    %% Tournées laboratoire
    LAB_TOURS ||--o{ LAB_TOUR_STOPS : "tour_id"
    LAB_TOURS ||--o{ LAB_TOUR_SHIPMENTS : "lab_tour_id"
    LAB_TOURS ||--o{ LAB_TOUR_LATE_STOPS : "lab_tour_id"

    LAB_TOUR_SHIPMENTS }o--|| LOCATIONS : "from_location_id"
    LAB_TOUR_SHIPMENTS }o--|| LOCATIONS : "to_location_id"

    %% Routes livreur
    DRIVER_ROUTES ||--o{ DRIVER_ROUTE_STOPS : "route_id"
    DRIVER_ROUTES ||--o{ DRIVER_ROUTE_SHIPMENTS : "route_id"

    DRIVER_ROUTE_STOPS }o--|| LOCATIONS : "location_id"
    DRIVER_ROUTE_SHIPMENTS }o--|| DRIVER_ROUTE_STOPS : "pickup_stop_id"
    DRIVER_ROUTE_SHIPMENTS }o--|| DRIVER_ROUTE_STOPS : "delivery_stop_id"
    DRIVER_ROUTE_SHIPMENTS }o--|| LABORATORIES : "laboratory_id"
    DRIVER_ROUTE_SHIPMENTS }o--o| LABORATORY_CLIENTS : "laboratory_client_id"

    %% Facturation
    BILLING_INVOICES ||--o{ BILLING_INVOICE_ITEMS : "invoice_id"
    BILLING_INVOICE_ITEMS }o--|| BILLING_CONFIGURATIONS : "billing_configuration_id"

    %% Autres
    LOCATIONS ||--o{ LOCATION_PHOTOS : "location_id"
    DEPOT ||--|| LOCATIONS : "location_id"

    %% Définitions des tables
    AUTH_USERS {
        uuid id PK
        string email
        timestamp created_at
    }

    LABORATORIES {
        uuid id PK
        uuid user_id FK
        string name
        uuid location_id FK
        boolean shared_pickup
    }

    DRIVERS {
        uuid id PK
        uuid user_id FK
        string full_name
        string sector
        time start_time
    }

    LABORATORY_CLIENTS {
        uuid id PK
        uuid laboratory_id FK
        uuid location_id FK
        uuid driver_id FK
        string name
        string client_type
    }

    LOCATIONS {
        uuid id PK
        string formatted_address
        decimal latitude
        decimal longitude
    }

    LAB_TOURS {
        uuid id PK
        uuid laboratory_id FK
        date date
        string status
    }

    LAB_TOUR_STOPS {
        uuid id PK
        uuid tour_id FK
        uuid client_id FK
        boolean has_pickup
        boolean has_delivery
    }

    DRIVER_ROUTES {
        uuid id PK
        uuid driver_id FK
        date date
        string status
        decimal total_distance_km
    }

    DRIVER_ROUTE_STOPS {
        uuid id PK
        uuid route_id FK
        uuid location_id FK
        int stop_order
        string stop_type
        boolean completed
    }

    DRIVER_ROUTE_SHIPMENTS {
        uuid id PK
        uuid route_id FK
        uuid pickup_stop_id FK
        uuid delivery_stop_id FK
        string pickup_status
        string delivery_status
        string proof_photo_url
    }
```

### Workflow métier complet

```mermaid
flowchart TB
    subgraph LAB["🏭 LABORATOIRE"]
        L1[Crée une tournée<br/>lab_tours.status = draft]
        L2[Ajoute les arrêts clients<br/>lab_tour_stops]
        L3[Soumet la tournée<br/>lab_tours.status = pending]
    end

    subgraph ADMIN["👨‍💼 ADMIN"]
        A1{Examine la<br/>tournée}
        A2[Valide<br/>status = validated]
        A3[Rejette<br/>status = rejected]
        A4[Génère les routes<br/>generate_driver_routes]
    end

    subgraph SYSTEM["⚙️ SYSTÈME"]
        S1[Crée driver_routes]
        S2[Génère driver_route_stops]
        S3[Génère driver_route_shipments]
        S4[Optimise la route<br/>Edge Function]
    end

    subgraph DRIVER["🚗 LIVREUR"]
        D1[Consulte sa route du jour]
        D2[Démarre la route<br/>status = in_progress]
        D3[Arrive à un arrêt]
        D4[Effectue pickup/delivery]
        D5[Prend photo preuve<br/>Edge Function]
        D6[Marque arrêt terminé]
        D7{Autres<br/>arrêts ?}
        D8[Termine la route<br/>status = completed]
    end

    subgraph BILLING["💰 FACTURATION"]
        B1[Fin de mois]
        B2[generate_monthly_invoice]
        B3[Facture générée]
        B4[mark_invoice_as_sent]
    end

    L1 --> L2 --> L3 --> A1
    A1 -->|Approuvée| A2
    A1 -->|Problème| A3
    A2 --> A4
    A3 -.->|Notification| L1

    A4 --> S1 --> S2 --> S3 --> S4

    S4 --> D1 --> D2 --> D3 --> D4 --> D5 --> D6 --> D7
    D7 -->|Oui| D3
    D7 -->|Non| D8

    D8 --> B1 --> B2 --> B3 --> B4

    style LAB fill:#e1f5fe
    style ADMIN fill:#fff3e0
    style SYSTEM fill:#f3e5f5
    style DRIVER fill:#e8f5e9
    style BILLING fill:#fce4ec
```

### Architecture des données

```mermaid
flowchart LR
    subgraph AUTH["🔐 Authentification"]
        AU[auth.users]
    end

    subgraph USERS["👥 Utilisateurs"]
        AD[administrators]
        AM[admins]
        LB[laboratories]
        DR[drivers]
    end

    subgraph GEO["📍 Géolocalisation"]
        LO[locations]
        LP[location_photos]
        DP[depot]
    end

    subgraph CLIENTS["🦷 Clients"]
        LC[laboratory_clients]
        LCA[laboratory_clients_audit]
    end

    subgraph TOURS["📋 Tournées Labo"]
        LT[lab_tours]
        LTS[lab_tour_stops]
        LTSH[lab_tour_shipments]
        LTLS[lab_tour_late_stops]
    end

    subgraph ROUTES["🚚 Routes Livreur"]
        DRO[driver_routes]
        DRS[driver_route_stops]
        DRSH[driver_route_shipments]
    end

    subgraph STATS["📊 Statistiques"]
        DST[driver_statistics]
        LST[laboratory_statistics]
        EL[error_logs]
    end

    subgraph BILLING["💳 Facturation"]
        BC[billing_configurations]
        BI[billing_invoices]
        BII[billing_invoice_items]
    end

    AU --> AD & AM & LB & DR
    LB --> LC
    DR --> LC
    LO --> LP
    LO --> DP
    LO --> LC
    LO --> LB
    LC --> LTS
    LT --> LTS & LTSH & LTLS

    LT -.->|generate_driver_routes| DRO
    DRO --> DRS & DRSH

    DR --> DST
    LB --> LST
    LB --> BI
    LC --> BC
    BI --> BII
    BC --> BII

    style AUTH fill:#ffcdd2
    style USERS fill:#c8e6c9
    style GEO fill:#b3e5fc
    style CLIENTS fill:#fff9c4
    style TOURS fill:#d1c4e9
    style ROUTES fill:#ffccbc
    style STATS fill:#b2dfdb
    style BILLING fill:#f8bbd9
```

### Cycle de vie d'une tournée

```mermaid
stateDiagram-v2
    [*] --> Draft: Création

    Draft --> Pending: Soumission
    Draft --> Draft: Modification

    Pending --> Validated: Approbation admin
    Pending --> Rejected: Rejet admin
    Pending --> PendingChanges: Demande modifications

    Rejected --> Draft: Correction
    PendingChanges --> Validated: Réapprobation

    Validated --> RouteGenerated: generate_driver_routes()

    RouteGenerated --> InProgress: Livreur démarre
    InProgress --> Completed: Tous arrêts terminés

    Completed --> [*]

    note right of Draft: lab_tours.status
    note right of RouteGenerated: driver_routes créée
    note right of InProgress: Suivi temps réel
```

### Types d'arrêts dans une route

```mermaid
flowchart LR
    subgraph ROUTE["Route du livreur"]
        direction TB
        START((🏠 Départ<br/>Domicile))

        DP[🏢 depot_pickup<br/>Récupération dépôt]

        LP1[🏭 lab_pickup<br/>Labo A]
        LP2[🏭 lab_pickup<br/>Labo B]

        C1[🦷 client<br/>Dentiste 1<br/>pickup]
        C2[🦷 client<br/>Dentiste 2<br/>delivery]
        C3[🦷 client<br/>Dentiste 3<br/>both]

        LD1[🏭 lab_dropoff<br/>Labo A]

        DD[🏢 depot_dropoff<br/>Dépôt final]

        END((🏠 Retour))
    end

    START --> DP --> LP1 --> LP2 --> C1 --> C2 --> C3 --> LD1 --> DD --> END

    style DP fill:#bbdefb
    style LP1 fill:#c8e6c9
    style LP2 fill:#c8e6c9
    style C1 fill:#fff9c4
    style C2 fill:#fff9c4
    style C3 fill:#fff9c4
    style LD1 fill:#c8e6c9
    style DD fill:#bbdefb
```

---

## Vue d'ensemble

Cette application gère les tournées de livraison entre laboratoires dentaires et leurs clients (dentistes/cabinets). Le système permet de :

- **Gérer les laboratoires** et leurs clients (dentistes)
- **Planifier des tournées** quotidiennes avec arrêts multiples
- **Générer automatiquement les routes** des livreurs
- **Suivre les livraisons** en temps réel avec preuves photos
- **Facturer automatiquement** les clients par mois
- **Analyser les statistiques** de performance

### Acteurs du système

| Rôle | Description | Authentification |
|------|-------------|------------------|
| **Administrator** | Super admin avec tous les droits | `administrators` + `auth.users` |
| **Admin** | Gestion quotidienne des tournées | `admins` + `auth.users` |
| **Laboratoire** | Soumet ses tournées, voit ses stats | `laboratories` + `auth.users` |
| **Livreur** | Exécute les routes, prend les photos | `drivers` + `auth.users` |

---

## Structure du repository

```
provence-courses-supabase/
│
├── README.md                         # Documentation complète
├── SECURITY_ADVISORIES.md            # Alertes de sécurité
├── config.toml                       # Configuration Supabase CLI
├── migrations.json                   # Liste des 178 migrations
│
├── database/                         # Dumps SQL complets (pg_dump)
│   ├── complete_schema.sql           # Schéma complet unifié
│   ├── schema_public.sql             # Tables, fonctions, triggers
│   ├── schema_auth.sql               # Supabase Auth
│   ├── schema_storage.sql            # Buckets et policies
│   ├── schema_realtime.sql           # Configuration realtime
│   ├── schema_extensions.sql         # Extensions PostgreSQL
│   └── roles.sql                     # Rôles de base de données
│
├── functions/                        # Edge Functions (Deno)
│   ├── delete-user/index.ts
│   ├── update-password/index.ts
│   ├── migrate-emails/index.ts
│   ├── optimize-route/index.ts
│   └── complete-delivery-with-photo/index.ts
│
├── types/                            # Types TypeScript générés
│   └── database.ts                   # Types complets pour le client
│
└── schemas/                          # Documentation complémentaire
    ├── storage.sql
    ├── extensions.sql
    ├── realtime.sql
    └── enums.sql
```

---

## Installation locale

### Prérequis

- **Docker Desktop** (obligatoire pour Supabase local)
- **Supabase CLI** v1.100+ ([Installation](https://supabase.com/docs/guides/cli))
- **PostgreSQL client** (psql) pour restaurer les dumps

### Méthode 1 : Restauration complète

```bash
# 1. Cloner le repository
git clone https://github.com/VOTRE_USERNAME/provence-courses-supabase.git
cd provence-courses-supabase

# 2. Démarrer Supabase local
supabase init  # Si pas déjà fait
supabase start

# 3. Récupérer les credentials locaux
supabase status
# Notez: DB URL, API URL, anon key, service_role key

# 4. Restaurer le schéma complet
psql "postgresql://postgres:postgres@localhost:54322/postgres" < database/complete_schema.sql

# 5. Déployer les Edge Functions
supabase functions deploy delete-user
supabase functions deploy update-password
supabase functions deploy optimize-route
supabase functions deploy complete-delivery-with-photo

# 6. Accéder au Studio local
open http://localhost:54323
```

### Méthode 2 : Restauration schéma par schéma

```bash
# Ordre de restauration important
psql $DATABASE_URL < database/roles.sql
psql $DATABASE_URL < database/schema_extensions.sql
psql $DATABASE_URL < database/schema_auth.sql
psql $DATABASE_URL < database/schema_storage.sql
psql $DATABASE_URL < database/schema_public.sql
psql $DATABASE_URL < database/schema_realtime.sql
```

### Variables d'environnement pour l'application

```env
# Pour le frontend
VITE_SUPABASE_URL=http://localhost:54321
VITE_SUPABASE_ANON_KEY=<votre-anon-key-local>

# Pour les Edge Functions
SUPABASE_URL=http://localhost:54321
SUPABASE_ANON_KEY=<votre-anon-key>
SUPABASE_SERVICE_ROLE_KEY=<votre-service-role-key>
```

---

## Architecture de la base de données

### Vue d'ensemble des tables

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AUTHENTIFICATION                                   │
├─────────────────┬─────────────────┬─────────────────┬───────────────────────┤
│  auth.users     │  administrators │     admins      │                       │
│  (45 users)     │  (1 super)      │   (3 admins)    │                       │
└────────┬────────┴────────┬────────┴────────┬────────┴───────────────────────┘
         │                 │                 │
         ▼                 ▼                 ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ENTITÉS MÉTIER                                       │
├─────────────────────────┬───────────────────────────────────────────────────┤
│      laboratories       │              drivers                               │
│      (39 labos)         │             (3 livreurs)                           │
│          │              │                  │                                 │
│          ▼              │                  ▼                                 │
│   laboratory_clients    │          driver_statistics                         │
│     (237 dentistes)     │         (stats par période)                        │
└─────────────────────────┴───────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                     GESTION DES LIEUX                                        │
├─────────────────────────┬───────────────────────────────────────────────────┤
│       locations         │           location_photos                          │
│    (243 adresses)       │         (38 photos de lieux)                       │
│  lat/lng/formatted_addr │                                                    │
└─────────────────────────┴───────────────────────────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    TOURNÉES LABORATOIRE (Demandes)                           │
├─────────────────────────┬─────────────────────┬─────────────────────────────┤
│       lab_tours         │   lab_tour_stops    │    lab_tour_shipments       │
│    (480 tournées)       │  (1601 arrêts)      │   (2063 expéditions)        │
│  status: pending →      │  has_pickup: bool   │  shipment_type: text        │
│  validated → completed  │  has_delivery: bool │  from/to_location_id        │
└─────────────────────────┴─────────────────────┴─────────────────────────────┘
                │
                │  generate_driver_routes()
                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ROUTES LIVREUR (Exécution)                                │
├─────────────────────────┬─────────────────────┬─────────────────────────────┤
│     driver_routes       │ driver_route_stops  │  driver_route_shipments     │
│    (127 routes)         │   (6241 arrêts)     │   (4715 expéditions)        │
│  status: pending →      │  stop_type: text    │  pickup_status: text        │
│  in_progress →          │  stop_order: int    │  delivery_status: text      │
│  completed              │  completed: bool    │  proof_photo_url: text      │
└─────────────────────────┴─────────────────────┴─────────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         FACTURATION                                          │
├─────────────────────────┬─────────────────────┬─────────────────────────────┤
│ billing_configurations  │   billing_invoices  │   billing_invoice_items     │
│    (21 configs)         │   (13 factures)     │    (23 lignes)              │
│  billing_type: text     │  invoice_number     │  line_total: decimal        │
│  price_per_visit        │  total_amount_euros │  total_visits: int          │
└─────────────────────────┴─────────────────────┴─────────────────────────────┘
```

---

## Schéma détaillé des tables

### Tables d'authentification

#### `administrators`
Super administrateurs du système avec accès total.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK, default uuid_generate_v4() | Identifiant unique |
| `user_id` | uuid | NOT NULL, FK → auth.users | Lien vers l'utilisateur Auth |
| `created_at` | timestamptz | default now() | Date de création |

#### `admins`
Administrateurs avec droits de gestion des tournées.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `user_id` | uuid | NOT NULL, FK → auth.users | Lien vers Auth |
| `created_at` | timestamptz | default now() | Date de création |

---

### Tables des entités métier

#### `laboratories`
Laboratoires dentaires clients du service.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `user_id` | uuid | NOT NULL, FK → auth.users | Compte utilisateur |
| `name` | text | NOT NULL | Nom du laboratoire |
| `email` | text | | Email de contact |
| `location_id` | uuid | NOT NULL, FK → locations | Adresse du labo |
| `depot_is_lab` | boolean | default false | Le labo est-il aussi un dépôt ? |
| `shared_pickup` | boolean | default false | Partage les récupérations |
| `created_at` | timestamptz | default now() | Date de création |

#### `drivers`
Livreurs effectuant les tournées.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `user_id` | uuid | NOT NULL, FK → auth.users | Compte utilisateur |
| `full_name` | text | NOT NULL | Nom complet |
| `email` | text | | Email |
| `start_address` | text | NOT NULL | Adresse de départ |
| `latitude` | numeric | | Latitude départ |
| `longitude` | numeric | | Longitude départ |
| `place_id` | text | | Google Place ID |
| `sector` | text | | Zone géographique assignée |
| `vehicle_type` | text | | Type de véhicule |
| `start_time` | time | default '08:00' | Heure de début |
| `created_at` | timestamptz | default now() | Date de création |

#### `laboratory_clients`
Dentistes/cabinets clients des laboratoires.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `laboratory_id` | uuid | NOT NULL, FK → laboratories | Labo parent |
| `location_id` | uuid | NOT NULL, FK → locations | Adresse |
| `driver_id` | uuid | FK → drivers | Livreur assigné |
| `name` | text | | Nom du client |
| `client_type` | text | NOT NULL | Type: 'dentist', 'clinic', etc. |
| `is_active` | boolean | default true | Client actif ? |
| `is_mika_client` | boolean | default false | Client Mika direct |
| `is_pickup_depot` | boolean | default false | Dépôt de récupération |
| `is_return_depot` | boolean | default false | Dépôt de retour |
| `is_return_next_day` | boolean | default false | Retour J+1 |
| `depot_is_dentist` | boolean | | Le dépôt est chez le dentiste |
| `depot_is_lab` | boolean | | Le dépôt est au labo |
| `created_at` | timestamptz | default now() | Date de création |

---

### Tables de géolocalisation

#### `locations`
Toutes les adresses géolocalisées du système.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `formatted_address` | text | NOT NULL | Adresse formatée |
| `latitude` | numeric | NOT NULL | Latitude GPS |
| `longitude` | numeric | NOT NULL | Longitude GPS |
| `place_id` | text | | Google Place ID |
| `type` | text | | Type: 'laboratory', 'client', 'depot' |
| `delivery_instructions` | text | | Instructions de livraison |
| `created_at` | timestamptz | default now() | Date de création |

#### `location_photos`
Photos des emplacements pour aider les livreurs.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `location_id` | uuid | NOT NULL, FK → locations | Location associée |
| `photo_url` | text | NOT NULL | URL dans Storage |
| `description` | text | | Description de la photo |
| `created_at` | timestamptz | default now() | Date de création |

#### `depot`
Dépôt central de distribution.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `name` | text | NOT NULL | Nom du dépôt |
| `location_id` | uuid | FK → locations | Adresse du dépôt |
| `is_active` | boolean | default true | Dépôt actif |
| `created_at` | timestamptz | default now() | Date de création |
| `updated_at` | timestamptz | | Dernière modification |

---

### Tables des tournées laboratoire

#### `lab_tours`
Tournées quotidiennes soumises par les laboratoires.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `laboratory_id` | uuid | NOT NULL, FK → laboratories | Laboratoire |
| `date` | date | NOT NULL | Date de la tournée |
| `status` | text | NOT NULL | 'draft', 'pending', 'validated', 'rejected', 'completed' |
| `pickup_time` | time | | Heure de récupération souhaitée |
| `return_time` | time | | Heure de retour souhaitée |
| `submission_time` | timestamptz | | Heure de soumission |
| `rejection_reason` | text | | Raison si rejetée |
| `created_at` | timestamptz | default now() | Date de création |

**Statuts possibles :**
- `draft` : Brouillon en cours d'édition
- `pending` : Soumise, en attente de validation
- `validated` : Validée par l'admin, prête pour génération de route
- `pending_changes` : Modifications demandées
- `rejected` : Rejetée par l'admin
- `completed` : Tournée terminée

#### `lab_tour_stops`
Arrêts demandés dans une tournée.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `tour_id` | uuid | NOT NULL, FK → lab_tours | Tournée parente |
| `client_id` | uuid | NOT NULL, FK → laboratory_clients | Client à visiter |
| `has_pickup` | boolean | default false | Récupération à faire |
| `has_delivery` | boolean | default false | Livraison à faire |
| `created_at` | timestamptz | default now() | Date de création |

#### `lab_tour_shipments`
Expéditions planifiées pour une tournée.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `lab_tour_id` | uuid | NOT NULL, FK → lab_tours | Tournée |
| `client_id` | uuid | FK → laboratory_clients | Client concerné |
| `from_location_id` | uuid | NOT NULL, FK → locations | Origine |
| `to_location_id` | uuid | NOT NULL, FK → locations | Destination |
| `shipment_type` | text | NOT NULL | Type d'expédition |
| `scheduled_date` | date | NOT NULL | Date prévue |
| `is_return_next_day` | boolean | default false | Retour J+1 |
| `created_at` | timestamptz | default now() | Date de création |

#### `lab_tour_late_stops`
Demandes de dernière minute (après validation).

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `lab_tour_id` | uuid | NOT NULL, FK → lab_tours | Tournée |
| `client_id` | uuid | NOT NULL, FK → laboratory_clients | Client |
| `has_pickup` | boolean | default false | Récupération |
| `has_delivery` | boolean | default false | Livraison |
| `status` | late_stop_status | default 'pending' | 'pending', 'approved', 'rejected' |
| `urgent_instructions` | text | | Instructions urgentes |
| `requested_at` | timestamptz | default now() | Heure de demande |
| `reviewed_at` | timestamptz | | Heure de review |
| `reviewed_by` | uuid | | Admin qui a traité |
| `rejection_reason` | text | | Raison si rejeté |
| `created_at` | timestamptz | default now() | Date de création |
| `updated_at` | timestamptz | | Dernière modification |

---

### Tables des routes livreur

#### `driver_routes`
Routes quotidiennes assignées aux livreurs.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `driver_id` | uuid | NOT NULL, FK → drivers | Livreur assigné |
| `date` | date | NOT NULL | Date de la route |
| `status` | text | NOT NULL | 'pending', 'optimized', 'in_progress', 'completed' |
| `total_distance_km` | numeric | | Distance totale en km |
| `estimated_duration` | integer | | Durée estimée en minutes |
| `polyline` | text | | Polyline encodée (Google) |
| `created_at` | timestamptz | default now() | Date de création |
| `updated_at` | timestamptz | | Dernière modification |

**Statuts possibles :**
- `pending` : Route générée, pas encore optimisée
- `optimized` : Route optimisée, prête à démarrer
- `in_progress` : Livreur en cours de tournée
- `completed` : Route terminée

#### `driver_route_stops`
Arrêts ordonnés dans une route de livreur.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `route_id` | uuid | NOT NULL, FK → driver_routes | Route parente |
| `location_id` | uuid | NOT NULL, FK → locations | Lieu de l'arrêt |
| `stop_order` | integer | NOT NULL | Ordre dans la route |
| `stop_type` | text | | Type d'arrêt (voir ci-dessous) |
| `client_actions` | text | | 'pickup', 'delivery', 'both' |
| `completed` | boolean | default false | Arrêt terminé |
| `arrival_time` | timestamptz | | Heure d'arrivée réelle |
| `estimated_arrival_time` | timestamptz | | Heure estimée |
| `estimated_departure_time` | timestamptz | | Heure de départ estimée |
| `distance_from_previous` | numeric | | Distance depuis l'arrêt précédent |
| `duration_from_previous` | integer | | Durée depuis l'arrêt précédent |
| `is_late_stop` | boolean | default false | Ajouté en dernière minute |
| `is_shared_pickup_stop` | boolean | default false | Récupération partagée |
| `created_at` | timestamptz | default now() | Date de création |

**Types d'arrêts (`stop_type`) :**
- `depot_pickup` : Récupération au dépôt central
- `depot_dropoff` : Dépôt au dépôt central
- `lab_pickup` : Récupération au laboratoire
- `lab_dropoff` : Livraison au laboratoire
- `client` : Arrêt chez un client (dentiste)

#### `driver_route_shipments`
Expéditions à réaliser pendant la route.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `route_id` | uuid | FK → driver_routes | Route associée |
| `laboratory_id` | uuid | NOT NULL, FK → laboratories | Labo concerné |
| `laboratory_client_id` | uuid | FK → laboratory_clients | Client concerné |
| `pickup_stop_id` | uuid | NOT NULL, FK → driver_route_stops | Arrêt de récup |
| `delivery_stop_id` | uuid | NOT NULL, FK → driver_route_stops | Arrêt de livraison |
| `shipment_ref` | text | | Référence lisible |
| `shipment_type` | text | | 'client_pickup', 'client_delivery', etc. |
| `pickup_status` | text | default 'pending' | 'pending', 'completed', 'failed' |
| `delivery_status` | text | default 'pending' | 'pending', 'completed', 'failed' |
| `pickup_time` | timestamptz | | Heure de récupération |
| `delivery_time` | timestamptz | | Heure de livraison |
| `proof_photo_url` | text | | URL de la photo preuve |
| `issue_type` | text | | Type de problème si échec |
| `issue_description` | text | | Description du problème |
| `unexpected` | boolean | default false | Expédition imprévue |
| `is_late_shipment` | boolean | default false | Ajoutée en dernière minute |
| `is_shared_pickup` | boolean | default false | Récupération partagée |
| `created_at` | timestamptz | default now() | Date de création |
| `updated_at` | timestamptz | | Dernière modification |

**Types de shipments (`shipment_type`) :**
- `client_delivery` : Livraison chez un client
- `client_pickup` : Récupération chez un client
- `lab_return` : Retour au laboratoire
- `lab_delivery` : Livraison au laboratoire

---

### Tables de facturation

#### `billing_configurations`
Configuration de facturation par client.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `laboratory_id` | uuid | NOT NULL, FK → laboratories | Laboratoire |
| `client_id` | uuid | NOT NULL, FK → laboratory_clients | Client |
| `billing_type` | text | NOT NULL | 'per_visit' ou 'flat_rate' |
| `price_per_visit` | numeric | | Prix par visite (si per_visit) |
| `monthly_flat_rate` | numeric | | Forfait mensuel (si flat_rate) |
| `effective_from` | date | default now() | Date de début |
| `effective_to` | date | | Date de fin (null = actif) |
| `is_active` | boolean | default true | Configuration active |
| `created_at` | timestamptz | default now() | Date de création |
| `updated_at` | timestamptz | | Dernière modification |

#### `billing_invoices`
Factures mensuelles générées.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `laboratory_id` | uuid | NOT NULL, FK → laboratories | Laboratoire facturé |
| `invoice_number` | text | NOT NULL, UNIQUE | Numéro de facture |
| `billing_period_start` | date | NOT NULL | Début de période |
| `billing_period_end` | date | NOT NULL | Fin de période |
| `total_amount_euros` | numeric | default 0 | Montant total |
| `status` | text | default 'draft' | 'draft', 'generated', 'sent', 'paid' |
| `generated_at` | timestamptz | default now() | Date de génération |
| `sent_at` | timestamptz | | Date d'envoi |
| `notes` | text | | Notes additionnelles |
| `created_at` | timestamptz | default now() | Date de création |
| `updated_at` | timestamptz | | Dernière modification |

#### `billing_invoice_items`
Lignes de détail des factures.

| Colonne | Type | Contraintes | Description |
|---------|------|-------------|-------------|
| `id` | uuid | PK | Identifiant unique |
| `invoice_id` | uuid | NOT NULL, FK → billing_invoices | Facture parente |
| `client_id` | uuid | NOT NULL, FK → laboratory_clients | Client concerné |
| `billing_configuration_id` | uuid | NOT NULL, FK → billing_configurations | Config utilisée |
| `billing_type` | text | NOT NULL | Type de facturation |
| `pickup_count` | integer | default 0 | Nombre de récupérations |
| `delivery_count` | integer | default 0 | Nombre de livraisons |
| `both_count` | integer | default 0 | Arrêts avec les deux |
| `total_visits` | integer | | Total des visites |
| `unit_price` | numeric | | Prix unitaire |
| `flat_rate` | numeric | | Forfait si applicable |
| `line_total` | numeric | NOT NULL | Total de la ligne |
| `created_at` | timestamptz | default now() | Date de création |

---

### Tables de statistiques

#### `driver_statistics`
Statistiques de performance des livreurs par période.

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | uuid | Identifiant unique |
| `driver_id` | uuid | Livreur concerné |
| `period_start` | date | Début de période |
| `period_end` | date | Fin de période |
| `total_working_days` | integer | Jours travaillés |
| `total_routes` | integer | Nombre de routes |
| `completed_routes` | integer | Routes terminées |
| `total_stops` | integer | Total des arrêts |
| `total_distance_km` | numeric | Distance parcourue |
| `average_duration_hours` | numeric | Durée moyenne |
| `average_stops_per_route` | numeric | Arrêts par route |
| `total_pickups` | integer | Récupérations |
| `total_deliveries` | integer | Livraisons |
| `completed_pickups` | integer | Récup réussies |
| `completed_deliveries` | integer | Livraisons réussies |
| `pickup_success_rate` | numeric | Taux réussite récup |
| `delivery_success_rate` | numeric | Taux réussite livraison |
| `route_completion_rate` | numeric | Taux complétion routes |
| `weekly_activity` | jsonb | Activité par jour |
| `hourly_distribution` | jsonb | Distribution horaire |
| `client_coverage` | jsonb | Clients couverts |
| `calculated_at` | timestamptz | Date de calcul |

#### `laboratory_statistics`
Statistiques de performance des laboratoires.

| Colonne | Type | Description |
|---------|------|-------------|
| `id` | uuid | Identifiant unique |
| `laboratory_id` | uuid | Laboratoire |
| `period_start` | date | Début de période |
| `period_end` | date | Fin de période |
| `total_shipments` | integer | Total expéditions |
| `completed_shipments` | integer | Expéditions réussies |
| `failed_shipments` | integer | Expéditions échouées |
| `success_rate` | numeric | Taux de succès |
| `failure_rate` | numeric | Taux d'échec |
| `most_delivered_client_id` | uuid | Client le + livré |
| `most_delivered_client_name` | text | Nom du client |
| `most_delivered_count` | integer | Nombre de livraisons |
| `least_delivered_client_id` | uuid | Client le - livré |
| `weekly_activity` | jsonb | Activité hebdo |
| `market_share_data` | jsonb | Part de marché |
| `calculated_at` | timestamptz | Date de calcul |

---

## Relations et clés étrangères

### Diagramme des relations principales

```
auth.users (Supabase Auth)
    │
    ├──── administrators.user_id
    ├──── admins.user_id
    ├──── laboratories.user_id
    └──── drivers.user_id

laboratories
    │
    ├──── location_id → locations.id
    ├──── laboratory_clients.laboratory_id
    ├──── lab_tours.laboratory_id
    ├──── billing_invoices.laboratory_id
    └──── billing_configurations.laboratory_id

drivers
    │
    ├──── laboratory_clients.driver_id
    ├──── driver_routes.driver_id
    └──── driver_statistics.driver_id

locations
    │
    ├──── laboratories.location_id
    ├──── laboratory_clients.location_id
    ├──── depot.location_id
    ├──── location_photos.location_id
    ├──── lab_tour_shipments.from_location_id
    ├──── lab_tour_shipments.to_location_id
    └──── driver_route_stops.location_id

laboratory_clients
    │
    ├──── lab_tour_stops.client_id
    ├──── lab_tour_late_stops.client_id
    ├──── lab_tour_shipments.client_id
    ├──── driver_route_shipments.laboratory_client_id
    ├──── billing_configurations.client_id
    └──── billing_invoice_items.client_id

lab_tours
    │
    ├──── lab_tour_stops.tour_id
    ├──── lab_tour_shipments.lab_tour_id
    └──── lab_tour_late_stops.lab_tour_id

driver_routes
    │
    ├──── driver_route_stops.route_id
    └──── driver_route_shipments.route_id

driver_route_stops
    │
    ├──── driver_route_shipments.pickup_stop_id
    └──── driver_route_shipments.delivery_stop_id
```

### Index importants

```sql
-- Performance des recherches par date
CREATE INDEX idx_lab_tours_date ON lab_tours(date);
CREATE INDEX idx_driver_routes_date ON driver_routes(date);

-- Recherche par statut
CREATE INDEX idx_lab_tours_status ON lab_tours(status);
CREATE INDEX idx_driver_routes_status ON driver_routes(status);

-- Relations fréquentes
CREATE INDEX idx_lab_tour_stops_tour_id ON lab_tour_stops(tour_id);
CREATE INDEX idx_driver_route_stops_route_id ON driver_route_stops(route_id);
CREATE INDEX idx_driver_route_shipments_route_id ON driver_route_shipments(route_id);
```

---

## Fonctions stockées PostgreSQL

### Génération de routes

#### `generate_driver_routes(target_date DATE)`

**Fonction principale** qui transforme les tournées laboratoire validées en routes livreur.

**Logique :**
1. Récupère le dépôt actif
2. Pour chaque date avec des `lab_tours` en statut `validated` ou `pending_changes` :
   - Supprime les routes existantes en `pending` ou `optimized`
   - Pour chaque livreur ayant des clients dans ces tournées :
     - Crée une nouvelle `driver_route`
     - Génère les arrêts dans l'ordre :
       - `depot_pickup` si des colis partent du dépôt
       - `lab_pickup` pour chaque labo source
       - `lab_dropoff` pour chaque labo destination
       - `client` pour chaque client avec pickup
       - `client` pour chaque client avec delivery
       - `depot_dropoff` si des colis arrivent au dépôt
     - Génère les `driver_route_shipments` correspondants

**Usage :**
```sql
-- Générer pour une date spécifique
SELECT generate_driver_routes('2024-01-15');

-- Générer pour toutes les dates avec tournées validées
SELECT generate_driver_routes(NULL);
```

#### `generate_driver_routes_v2(target_date DATE)`

Version améliorée avec optimisations et meilleure gestion des cas limites.

#### `generate_lab_tour_shipments(lab_tour_id UUID)`

Génère automatiquement les expéditions (`lab_tour_shipments`) depuis les arrêts d'une tournée.

**Usage :**
```sql
SELECT generate_lab_tour_shipments('uuid-de-la-tournee');
```

---

### Calcul de statistiques

#### `calculate_driver_statistics(driver_id UUID, period_start DATE, period_end DATE)`

Calcule et stocke les statistiques d'un livreur pour une période donnée.

**Métriques calculées :**
- Jours travaillés, routes totales/complétées
- Distance parcourue, durée moyenne
- Taux de succès pickup/delivery
- Distribution hebdomadaire de l'activité
- Clients assignés (JSON)

**Usage :**
```sql
SELECT calculate_driver_statistics(
  'driver-uuid',
  '2024-01-01',
  '2024-01-31'
);
```

#### `calculate_laboratory_statistics(lab_id UUID, period_start DATE, period_end DATE)`

Statistiques similaires pour un laboratoire.

#### `refresh_all_driver_statistics(period_start DATE, period_end DATE)`

Rafraîchit les stats de tous les livreurs pour une période.

```sql
SELECT refresh_all_driver_statistics('2024-01-01', '2024-01-31');
```

---

### Facturation

#### `generate_monthly_invoice(lab_id UUID, billing_month DATE)`

Génère une facture mensuelle pour un laboratoire.

**Logique :**
1. Récupère toutes les `billing_configurations` actives du labo
2. Pour chaque client :
   - Compte les visites (pickups, deliveries, both)
   - Applique le prix selon le type (per_visit ou flat_rate)
   - Crée une ligne de facture
3. Calcule le total et crée la facture

**Usage :**
```sql
SELECT generate_monthly_invoice('lab-uuid', '2024-01-01');
```

#### `generate_invoice_number(lab_id UUID, period_start DATE)`

Génère un numéro de facture unique au format `FAC-YYYY-MM-NNNN`.

#### `mark_invoice_as_sent(invoice_id UUID)`

Marque une facture comme envoyée et enregistre la date d'envoi.

---

### Utilitaires

#### `add_unexpected_shipment(...)`

Ajoute une expédition imprévue pendant une route en cours.

```sql
SELECT add_unexpected_shipment(
  p_route_id := 'route-uuid',
  p_pickup_stop_id := 'stop-uuid',
  p_laboratory_id := 'lab-uuid',
  p_laboratory_client_id := 'client-uuid',
  p_shipment_ref := 'Récupération imprévue',
  p_proof_photo_url := 'https://...'
);
```

#### `delete_client_complete(client_id UUID, location_id UUID)`

Supprime un client et toutes ses dépendances (tournées, stats, etc.).

#### `analyze_route_state(route_id UUID)`

Retourne un JSON avec l'état détaillé d'une route :
```json
{
  "route_id": "...",
  "status": "in_progress",
  "stops_count": 15,
  "shipments_count": 20,
  "stop_types": {
    "client": 10,
    "lab_pickup": 2,
    "depot_dropoff": 1
  },
  "needs_fusion": false
}
```

---

## Edge Functions (Deno)

Les Edge Functions sont des fonctions serverless qui s'exécutent sur le edge network de Supabase.

### `delete-user`

**Objectif :** Supprimer complètement un utilisateur de Supabase Auth avec des droits admin.

**Endpoint :** `POST /functions/v1/delete-user`

**Body :**
```json
{
  "userId": "uuid-de-l-utilisateur",
  "apiKey": "cle-api-optionnelle"
}
```

**Réponse :**
```json
{
  "success": true,
  "message": "Utilisateur supprimé avec succès"
}
```

**Variables d'environnement requises :**
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `API_KEY` (optionnel, pour sécurité additionnelle)

---

### `update-password`

**Objectif :** Modifier le mot de passe d'un utilisateur (admin only).

**Endpoint :** `POST /functions/v1/update-password`

**Body :**
```json
{
  "userId": "uuid-de-l-utilisateur",
  "newPassword": "nouveau-mot-de-passe",
  "apiKey": "cle-api-optionnelle"
}
```

**Réponse :**
```json
{
  "success": true,
  "message": "Mot de passe mis à jour avec succès"
}
```

---

### `optimize-route`

**Objectif :** Optimiser l'ordre des arrêts d'une route livreur.

**Endpoint :** `POST /functions/v1/optimize-route`

**Body :**
```json
{
  "routeId": "uuid-de-la-route"
}
```

**Logique :**
1. Récupère la route et ses arrêts
2. Récupère les coordonnées du livreur (point de départ)
3. Appelle un service d'optimisation de route
4. Met à jour l'ordre des arrêts
5. Calcule les temps estimés

---

### `complete-delivery-with-photo`

**Objectif :** Compléter une livraison avec upload de photo de preuve de manière **atomique**.

**Endpoint :** `POST /functions/v1/complete-delivery-with-photo`

**Body :**
```json
{
  "shipmentId": "uuid-du-shipment",
  "photoBase64": "data:image/jpeg;base64,...",
  "actionType": "delivery",
  "status": "completed",
  "issueType": "absent",
  "issueDescription": "Client absent, laissé chez le voisin"
}
```

**Garanties :**
- **Atomicité** : Si l'upload échoue, rien n'est modifié
- **Rollback automatique** : Si la mise à jour DB échoue, la photo est supprimée
- **Validation** : Vérifie que le shipment existe avant tout traitement

**Réponse :**
```json
{
  "success": true,
  "photoUrl": "https://...supabase.co/storage/v1/object/public/photos-delivery/...",
  "shipment": { ... }
}
```

---

### `migrate-emails`

**Objectif :** Migrer les emails depuis Supabase Auth vers les tables `laboratories` et `drivers`.

Utilisé lors de migrations de données.

---

## Storage et buckets

### Buckets configurés

| Bucket | Public | Usage |
|--------|--------|-------|
| `location-photos` | Oui | Photos des emplacements de livraison |
| `photos-delivery` | Oui | Preuves de livraison (photos livreurs) |

### Structure des fichiers

```
location-photos/
├── location_{uuid}_{timestamp}.jpg
└── ...

photos-delivery/
├── photos/
│   ├── shipment_{uuid}_{timestamp}.jpg
│   └── ...
└── ...
```

### Policies de storage

Les buckets sont publics en lecture pour permettre l'affichage des images dans l'application. L'écriture nécessite une authentification.

---

## Configuration Realtime

Supabase Realtime est configuré pour permettre les mises à jour en temps réel sur :

- `driver_routes` - Changements de statut des routes
- `driver_route_stops` - Progression des arrêts
- `driver_route_shipments` - Statut des livraisons
- `lab_tours` - Validation/rejet des tournées

### Exemple d'utilisation côté client

```typescript
const subscription = supabase
  .channel('driver-route-changes')
  .on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'driver_route_shipments',
      filter: `route_id=eq.${routeId}`
    },
    (payload) => {
      console.log('Shipment updated:', payload.new);
    }
  )
  .subscribe();
```

---

## Types TypeScript

Le fichier `types/database.ts` contient tous les types TypeScript générés depuis le schéma.

### Utilisation avec le client Supabase

```typescript
import { createClient } from '@supabase/supabase-js';
import { Database } from './types/database';

const supabase = createClient<Database>(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_ANON_KEY!
);

// Les types sont automatiquement inférés
const { data: labs } = await supabase
  .from('laboratories')
  .select('*');

// labs est de type Database['public']['Tables']['laboratories']['Row'][] | null
```

### Types disponibles

```typescript
// Tables
type Laboratory = Database['public']['Tables']['laboratories']['Row'];
type Driver = Database['public']['Tables']['drivers']['Row'];
type LabTour = Database['public']['Tables']['lab_tours']['Row'];
type DriverRoute = Database['public']['Tables']['driver_routes']['Row'];

// Insert/Update
type NewLaboratory = Database['public']['Tables']['laboratories']['Insert'];
type UpdateLaboratory = Database['public']['Tables']['laboratories']['Update'];

// Enums
type LateStopStatus = Database['public']['Enums']['late_stop_status'];
// = 'pending' | 'approved' | 'rejected'

// Fonctions
type GenerateDriverRoutes = Database['public']['Functions']['generate_driver_routes'];
```

---

## Workflow métier

### 1. Soumission de tournée (Laboratoire)

```
┌─────────────────────────────────────────────────────────────────┐
│  1. LABORATOIRE crée une tournée pour une date                  │
│     → lab_tours.status = 'draft'                                │
│                                                                  │
│  2. Ajoute les arrêts (clients à visiter)                       │
│     → lab_tour_stops (client_id, has_pickup, has_delivery)      │
│                                                                  │
│  3. Soumet la tournée                                           │
│     → lab_tours.status = 'pending'                              │
│     → generate_lab_tour_shipments() génère les expéditions      │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Validation (Admin)

```
┌─────────────────────────────────────────────────────────────────┐
│  4. ADMIN examine les tournées en attente                       │
│     → Liste des lab_tours WHERE status = 'pending'              │
│                                                                  │
│  5. Valide ou rejette                                           │
│     → lab_tours.status = 'validated' | 'rejected'               │
│     → Si rejetée : lab_tours.rejection_reason = '...'           │
│                                                                  │
│  6. Génère les routes livreur                                   │
│     → SELECT generate_driver_routes('2024-01-15');              │
│     → Crée driver_routes, driver_route_stops, driver_route_shipments │
└─────────────────────────────────────────────────────────────────┘
```

### 3. Exécution (Livreur)

```
┌─────────────────────────────────────────────────────────────────┐
│  7. LIVREUR consulte sa route du jour                           │
│     → driver_routes WHERE driver_id = X AND date = TODAY        │
│                                                                  │
│  8. Démarre la route                                            │
│     → driver_routes.status = 'in_progress'                      │
│                                                                  │
│  9. Pour chaque arrêt :                                         │
│     a. Arrive sur place                                         │
│        → driver_route_stops.arrival_time = NOW()                │
│     b. Effectue les actions (pickup/delivery)                   │
│        → driver_route_shipments.pickup_status = 'completed'     │
│        → Prend photo de preuve                                  │
│        → Edge Function complete-delivery-with-photo             │
│     c. Marque l'arrêt comme terminé                             │
│        → driver_route_stops.completed = true                    │
│                                                                  │
│  10. Termine la route                                           │
│      → driver_routes.status = 'completed'                       │
└─────────────────────────────────────────────────────────────────┘
```

### 4. Facturation (Admin)

```
┌─────────────────────────────────────────────────────────────────┐
│  11. En fin de mois, ADMIN génère les factures                  │
│      → SELECT generate_monthly_invoice(lab_id, '2024-01-01');   │
│                                                                  │
│  12. Vérifie et envoie les factures                             │
│      → SELECT mark_invoice_as_sent(invoice_id);                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Notes de sécurité

### Avertissements actuels

> **Consulter `SECURITY_ADVISORIES.md` pour le détail complet**

| Niveau | Problème | Tables/Fonctions concernées |
|--------|----------|----------------------------|
| Warning | 18 tables sans RLS | Voir liste dans SECURITY_ADVISORIES.md |
| Warning | 6 views avec SECURITY DEFINER | billing_reports, v_driver_*, etc. |
| Warning | 40+ fonctions avec search_path mutable | Fonctions de génération et stats |

### Recommandations

1. **Activer RLS** sur toutes les tables public :
```sql
ALTER TABLE laboratories ENABLE ROW LEVEL SECURITY;
```

2. **Créer des policies** appropriées :
```sql
CREATE POLICY "Users can view own laboratory"
ON laboratories FOR SELECT
USING (auth.uid() = user_id);
```

3. **Fixer le search_path** des fonctions :
```sql
ALTER FUNCTION generate_driver_routes SET search_path = public;
```

4. **Mettre à jour PostgreSQL** vers la dernière version stable.

---

## Support

Pour toute question sur la structure de la base de données ou l'architecture de l'application, contactez l'équipe technique.

---

*Export généré le 2026-01-23*
