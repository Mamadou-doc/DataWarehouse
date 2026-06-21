/*====================================================================================================

    PROJET : Analyse Commerciale et Niveau de Vie
    AUTEUR : Mamadou TANDIAN 
    DESCRIPTION : Script complet de création de la base de données
    
====================================================================================================*/

/*==============================================================
    PARTIE 1 : CREATION DE LA BASE DE DONNEES
==============================================================*/

CREATE DATABASE DW_VilleCommerce;
GO

USE DW_VilleCommerce;
GO

/*==============================================================
    PARTIE 2 : CREATION DES TABLES 
==============================================================*/

-- 2.1 Dimension Temps
CREATE TABLE DimTemps (
    id_temps INT IDENTITY(1,1) PRIMARY KEY,
    annee INT NOT NULL UNIQUE
);
GO

-- 2.2 Dimension Département 
CREATE TABLE DimDepartement (
    id_departement CHAR(3) PRIMARY KEY,
    nom_departement VARCHAR(100),
    code_region CHAR(2),
    nom_region VARCHAR(100)
);
GO

-- 2.3 Dimension Ville 
CREATE TABLE DimVille (
    id_ville INT IDENTITY(1,1) PRIMARY KEY,
    code_insee VARCHAR(10),
    nom_ville VARCHAR(255) NOT NULL,
    id_departement CHAR(3),
    latitude DECIMAL(10,8),
    longitude DECIMAL(11,8),
    date_validite_debut DATE,
    date_validite_fin DATE,
    is_current BIT DEFAULT 1,
    FOREIGN KEY (id_departement) REFERENCES DimDepartement(id_departement)
);
GO

-- 2.4 Dimension Catégorie de Commerce
CREATE TABLE DimCategorieCommerce (
    id_categorie INT IDENTITY(1,1) PRIMARY KEY,
    libelle_categorie VARCHAR(50) NOT NULL UNIQUE
);
GO

-- 2.5 Dimension Type de Commerce
CREATE TABLE DimTypeCommerce (
    id_type_commerce INT IDENTITY(1,1) PRIMARY KEY,
    libelle_type_commerce VARCHAR(100) NOT NULL UNIQUE,
    id_categorie INT NOT NULL,
    FOREIGN KEY (id_categorie) REFERENCES DimCategorieCommerce(id_categorie)
);
GO

-- 2.6 Table de faits
CREATE TABLE FactCommerce (
    id_fact_commerce BIGINT IDENTITY(1,1) PRIMARY KEY,
    id_ville INT NOT NULL,
    id_temps INT NOT NULL,
    id_type_commerce INT NOT NULL,
    nombre_commerces INT DEFAULT 0,
    population_ville INT,
    menages_imposes INT,
    niveau_de_vie_median DECIMAL(10,2),
    date_import DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (id_ville) REFERENCES DimVille(id_ville),
    FOREIGN KEY (id_temps) REFERENCES DimTemps(id_temps),
    FOREIGN KEY (id_type_commerce) REFERENCES DimTypeCommerce(id_type_commerce)
);
GO

-- 2.7 Index
CREATE INDEX idx_FactCommerce_ville ON FactCommerce(id_ville);
CREATE INDEX idx_FactCommerce_temps ON FactCommerce(id_temps);
CREATE INDEX idx_FactCommerce_type ON FactCommerce(id_type_commerce);
CREATE INDEX idx_DimVille_departement ON DimVille(id_departement);
CREATE INDEX idx_DimVille_nom ON DimVille(nom_ville);
GO

/*==============================================================
    PARTIE 3 : INSERTION DES CATEGORIES (Exception)
==============================================================*/

INSERT INTO DimCategorieCommerce (libelle_categorie) VALUES 
('GRANDE_SURFACE'),
('PROXIMITE'),
('AUTRE'),
('ELECTRONIQUE');
GO

/*==============================================================
    PARTIE 4 : CREATION DE TABLES TAMPORAIRES POUR LE PEUPLEMENT DE LA BASE DE DONNEES 
==============================================================*/

CREATE TABLE Staging_VilleSpatial (
    id_staging INT IDENTITY(1,1) PRIMARY KEY,
    id_departement VARCHAR(10),
    libelle_de_commune VARCHAR(255),
    latitude VARCHAR(50),
    longitude VARCHAR(50),
    date_import DATETIME DEFAULT GETDATE()
);
GO

CREATE TABLE Staging_NiveauVie (
    id_staging INT IDENTITY(1,1) PRIMARY KEY,
    ville VARCHAR(255),
    mediane_niveau_de_vie_2019 VARCHAR(50),
    part_menages_fiscaux_imposes_2019 VARCHAR(50),
    date_import DATETIME DEFAULT GETDATE()
);
GO

CREATE TABLE Staging_Commerce_Brut (
    id_ligne INT IDENTITY(1,1) PRIMARY KEY,
    ligne_texte VARCHAR(MAX),
    date_import DATETIME DEFAULT GETDATE()
);
GO

CREATE TABLE Staging_Commerce_Clean (
    id_departement VARCHAR(10),
    libelle_de_commune VARCHAR(255),
    annee VARCHAR(20),
    population VARCHAR(50),
    type_commerce VARCHAR(255),
    nombre_commerces VARCHAR(50)
);
GO


/*==============================================================
    PARTIE 5 : PEUPLEMENT DE DimTypeCommerce (exception via SQL)
    Récupération des types et catégories depuis Staging_Commerce_Brut
==============================================================*/

DELETE FROM DimTypeCommerce;
GO

WITH TypesBruts AS (
    SELECT 
        value AS type_commerce,
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS ordre_colonne
    FROM Staging_Commerce_Brut
    CROSS APPLY STRING_SPLIT(ligne_texte, ';')
    WHERE id_ligne = 2
),
CategoriesBruts AS (
    SELECT 
        value AS categorie,
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS ordre_colonne
    FROM Staging_Commerce_Brut
    CROSS APPLY STRING_SPLIT(ligne_texte, ';')
    WHERE id_ligne = 1
)
INSERT INTO DimTypeCommerce (libelle_type_commerce, id_categorie)
SELECT 
    t.type_commerce,
    c.id_categorie
FROM TypesBruts t
INNER JOIN CategoriesBruts cat ON t.ordre_colonne = cat.ordre_colonne
INNER JOIN DimCategorieCommerce c ON c.libelle_categorie = cat.categorie
WHERE t.type_commerce NOT IN ('id_departement', 'libelle_de_commune', 'annee', 'population')
  AND t.type_commerce IS NOT NULL
  AND t.type_commerce <> '';
GO


/*==============================================================
    PARTIE 6 : MODIFICATIONS APRES PEUPLEMENT SSIS
    Ces colonnes se sont révélées inutiles car non renseignées
==============================================================*/

-- 5.1 Suppression des colonnes inutilisées dans DimDepartement
ALTER TABLE DimDepartement DROP COLUMN nom_departement, code_region, nom_region;
GO

-- 5.2 Suppression de code_insee dans DimVille (non disponible dans les sources)
ALTER TABLE DimVille DROP COLUMN code_insee;
GO

-- 5.3 Suppression des tables staging car non  utilisées
DROP TABLE IF EXISTS Staging_Commerce;
DROP TABLE IF EXISTS Staging_Commerce_Mapping;
GO



/*==============================================================
    PARTIE 7 : MISE A JOUR DES DATES POUR LA GESTION DES SCD
    Les données correspondent à l'année de référence 2019
==============================================================*/

UPDATE DimVille 
SET 
    date_validite_debut = '2019-01-01',
    date_validite_fin = NULL,
    is_current = 1
WHERE id_ville IS NOT NULL;
GO

/*==============================================================
    PARTIE 8 : ANALYSES DEMANDEES DANS LE PROJET
==============================================================*/

-- 8.1 Densité des commerces par type de commerce
SELECT 
    tc.libelle_type_commerce,
    SUM(f.nombre_commerces) AS total_commerces,
    AVG(f.menages_imposes) AS avg_menages_imposes,
    CASE 
        WHEN AVG(CAST(f.menages_imposes AS FLOAT)) > 0 
        THEN SUM(CAST(f.nombre_commerces AS BIGINT)) * 1000.0 / AVG(CAST(f.menages_imposes AS FLOAT))
        ELSE 0 
    END AS densite_pour_1000_menages
FROM FactCommerce f
INNER JOIN DimTypeCommerce tc ON f.id_type_commerce = tc.id_type_commerce
GROUP BY tc.libelle_type_commerce
ORDER BY densite_pour_1000_menages DESC;
GO

-- 8.2 Villes d'Île-de-France avec le niveau de vie le plus élevé
SELECT TOP 20
    v.nom_ville,
    v.id_departement,
    f.niveau_de_vie_median
FROM FactCommerce f
INNER JOIN DimVille v ON f.id_ville = v.id_ville
WHERE v.id_departement IN ('75','77','78','91','92','93','94','95')
  AND f.niveau_de_vie_median IS NOT NULL
ORDER BY f.niveau_de_vie_median DESC;
GO

-- 8.3 Corrélation niveau de vie / ménages imposés
SELECT 
    v.nom_ville,
    AVG(f.niveau_de_vie_median) AS niveau_vie_moyen,
    AVG(CAST(f.menages_imposes AS FLOAT)) AS menages_imposes_moyen
FROM FactCommerce f
INNER JOIN DimVille v ON f.id_ville = v.id_ville
WHERE f.niveau_de_vie_median IS NOT NULL
  AND f.menages_imposes IS NOT NULL
GROUP BY v.nom_ville
ORDER BY niveau_vie_moyen DESC;
GO

-- 8.4 Villes des 10% avec niveau de vie élevé
WITH Classement AS (
    SELECT 
        v.nom_ville,
        AVG(f.niveau_de_vie_median) AS niveau_vie,
        PERCENT_RANK() OVER (ORDER BY AVG(f.niveau_de_vie_median) DESC) AS rang
    FROM FactCommerce f
    INNER JOIN DimVille v ON f.id_ville = v.id_ville
    WHERE f.niveau_de_vie_median IS NOT NULL
    GROUP BY v.nom_ville
)
SELECT nom_ville, niveau_vie
FROM Classement
WHERE rang <= 0.1
ORDER BY niveau_vie DESC;
GO

-- 8.5 Villes des 10% avec niveau de vie bas
WITH Classement AS (
    SELECT 
        v.nom_ville,
        AVG(f.niveau_de_vie_median) AS niveau_vie,
        PERCENT_RANK() OVER (ORDER BY AVG(f.niveau_de_vie_median) ASC) AS rang
    FROM FactCommerce f
    INNER JOIN DimVille v ON f.id_ville = v.id_ville
    WHERE f.niveau_de_vie_median IS NOT NULL
    GROUP BY v.nom_ville
)
SELECT nom_ville, niveau_vie
FROM Classement
WHERE rang <= 0.1
ORDER BY niveau_vie ASC;
GO

-- 8.6 Villes avec niveau de vie moyen (40% du milieu)
WITH Classement AS (
    SELECT 
        v.nom_ville,
        AVG(f.niveau_de_vie_median) AS niveau_vie,
        PERCENT_RANK() OVER (ORDER BY AVG(f.niveau_de_vie_median) DESC) AS rang
    FROM FactCommerce f
    INNER JOIN DimVille v ON f.id_ville = v.id_ville
    WHERE f.niveau_de_vie_median IS NOT NULL
    GROUP BY v.nom_ville
)
SELECT nom_ville, niveau_vie
FROM Classement
WHERE rang BETWEEN 0.3 AND 0.7
ORDER BY niveau_vie DESC;
GO

-- 8.7 Recommandation pour l'ouverture de 5 poissonneries
SELECT TOP 10
    v.nom_ville,
    SUM(f.population_ville) AS population_totale,
    SUM(CASE WHEN tc.libelle_type_commerce = 'poissonnerie' THEN f.nombre_commerces ELSE 0 END) AS nb_poissonneries,
    CASE 
        WHEN SUM(CASE WHEN tc.libelle_type_commerce = 'poissonnerie' THEN f.nombre_commerces ELSE 0 END) > 0
        THEN SUM(f.population_ville) / SUM(CASE WHEN tc.libelle_type_commerce = 'poissonnerie' THEN f.nombre_commerces ELSE 0 END)
        ELSE SUM(f.population_ville)
    END AS habitants_par_poissonnerie
FROM FactCommerce f
INNER JOIN DimVille v ON f.id_ville = v.id_ville
INNER JOIN DimTypeCommerce tc ON f.id_type_commerce = tc.id_type_commerce
GROUP BY v.nom_ville
HAVING SUM(CASE WHEN tc.libelle_type_commerce = 'poissonnerie' THEN f.nombre_commerces ELSE 0 END) < 3
ORDER BY population_totale DESC;
GO

/*==============================================================
    PARTIE 9 : Vider les tables temporaies 
    À exécuter APRÈS avoir vérifié le bon peuplement des tables finales
==============================================================*/

-- TRUNCATE TABLE Staging_VilleSpatial;
-- TRUNCATE TABLE Staging_NiveauVie;
-- TRUNCATE TABLE Staging_Commerce_Brut;
-- TRUNCATE TABLE Staging_Commerce_Clean;

USE DW_VilleCommerce;
GO

SELECT COUNT(*) AS FactCommerce FROM FactCommerce;
SELECT COUNT(*) AS DimVille FROM DimVille;
SELECT COUNT(*) AS DimTemps FROM DimTemps;
SELECT COUNT(*) AS DimTypeCommerce FROM DimTypeCommerce;
SELECT COUNT(*) AS DimDepartement FROM DimDepartement;

/*==============================================================
    FIN DU SCRIPT
==============================================================*/


USE DW_VilleCommerce;
GO

-- 1. Vider les tables staging (si ce n'est pas déjà fait)
TRUNCATE TABLE Staging_VilleSpatial;
TRUNCATE TABLE Staging_NiveauVie;
TRUNCATE TABLE Staging_Commerce_Brut;
TRUNCATE TABLE Staging_Commerce_Clean;
GO

-- 2. Nettoyer les logs
CHECKPOINT;
GO

-- 3. Libérer la mémoire cache
DBCC FREEPROCCACHE;
DBCC DROPCLEANBUFFERS;
GO

-- 4. Réduire la taille de la base pour pouvoir chargé rapidement sur Power BI 
DBCC SHRINKDATABASE (DW_VilleCommerce);
GO

EXEC sp_spaceused 'FactCommerce';
GO



SELECT 
    v.nom_ville,
    AVG(f.niveau_de_vie_median) AS niveau_vie,
    SUM(CAST(f.population_ville AS BIGINT)) AS population
FROM FactCommerce f
INNER JOIN DimVille v ON f.id_ville = v.id_ville
GROUP BY v.nom_ville
ORDER BY niveau_vie DESC;


SELECT 
    v.nom_ville,
    AVG(f.niveau_de_vie_median) AS niveau_vie,
    AVG(CAST(f.population_ville AS BIGINT)) AS population
FROM FactCommerce f
INNER JOIN DimVille v ON f.id_ville = v.id_ville
GROUP BY v.nom_ville
ORDER BY niveau_vie DESC;


-- Vue 1 : Top 10% niveau de vie élevé -- 
CREATE VIEW Vue_10pc_Eleve AS
WITH Base AS (
    SELECT 
        v.nom_ville,
        AVG(f.niveau_de_vie_median) AS niveau_vie,
        AVG(CAST(f.population_ville AS BIGINT)) AS population
    FROM FactCommerce f
    INNER JOIN DimVille v ON f.id_ville = v.id_ville
    GROUP BY v.nom_ville
),
Cumul AS (
    SELECT 
        nom_ville,
        niveau_vie,
        population,
        SUM(population) OVER (ORDER BY niveau_vie DESC) AS cumul_pop,
        SUM(population) OVER () AS total_pop
    FROM Base
)
SELECT 
    nom_ville,
    niveau_vie,
    population,
    cumul_pop,
    cumul_pop * 1.0 / total_pop AS pc_cumul
FROM Cumul;

-- Vue 2 : Bottom 10% niveau de vie bas

CREATE VIEW Vue_10pc_Bas AS
WITH Base AS (
    SELECT 
        v.nom_ville,
        AVG(f.niveau_de_vie_median) AS niveau_vie,
        AVG(CAST(f.population_ville AS BIGINT)) AS population
    FROM FactCommerce f
    INNER JOIN DimVille v ON f.id_ville = v.id_ville
    GROUP BY v.nom_ville
),
Cumul AS (
    SELECT 
        nom_ville,
        niveau_vie,
        population,
        SUM(population) OVER (ORDER BY niveau_vie ASC) AS cumul_pop,
        SUM(population) OVER () AS total_pop
    FROM Base
)
SELECT 
    nom_ville,
    niveau_vie,
    population,
    cumul_pop,
    cumul_pop * 1.0 / total_pop AS pc_cumul
FROM Cumul;

-- Vue 3 : Niveau de vie moyen (30-70%)

CREATE VIEW Vue_10pc_Moyen AS
SELECT 
    v.nom_ville,
    AVG(f.niveau_de_vie_median) AS niveau_vie,
    AVG(CAST(f.population_ville AS BIGINT)) AS population
FROM FactCommerce f
INNER JOIN DimVille v ON f.id_ville = v.id_ville
GROUP BY v.nom_ville
HAVING AVG(f.niveau_de_vie_median) BETWEEN 22000 AND 27000;

-- Vue 4 : Répartition des commerces par type

CREATE VIEW Vue_Repartition_Commerce AS
SELECT 
    v.nom_ville,
    tc.libelle_type_commerce,
    SUM(f.nombre_commerces) AS nb_commerces,
    AVG(f.niveau_de_vie_median) AS niveau_vie
FROM FactCommerce f
INNER JOIN DimVille v ON f.id_ville = v.id_ville
INNER JOIN DimTypeCommerce tc ON f.id_type_commerce = tc.id_type_commerce
GROUP BY v.nom_ville, tc.libelle_type_commerce;