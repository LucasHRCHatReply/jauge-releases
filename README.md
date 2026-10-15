# Jauge pour macOS

Jauge garde la batterie d'un MacBook entre deux niveaux (par exemple 55 % et 60 %) quand il est branché, au lieu
de la laisser à 100 % en permanence : la batterie vieillit moins vite. L'app vit dans la barre des menus ;
elle affiche aussi où vont les watts, l'historique de charge et les appareils branchés.

Ce dépôt ne contient que les versions à installer. Le code source n'est pas public.

## Ce qu'il faut

- un MacBook à puce Apple (M1 ou plus récent) ;
- macOS 26 ou plus ;
- si AlDente, batt ou une autre app de limite de charge est installée : la quitter, deux apps qui pilotent la
  charge se contredisent.

Aucun compte GitHub, aucun outil à installer, aucun mot de passe administrateur.

## Installer

Dans Terminal (Cmd + Espace, « Terminal »), une seule commande, qui installe aussi les mises à jour :

```
curl -fsSL https://raw.githubusercontent.com/LucasHRCHatReply/jauge-releases/main/installer.sh | zsh
```

Le script télécharge la dernière version, vérifie la signature (équipe Apple `JT9FY7PP7K`, `codesign --verify
--deep --strict`), copie `Jauge.app` dans `~/Applications`, puis l'ouvre. Il garde réglages, historique et
appareils. Une seule étape reste manuelle, une fois : Réglages Système › Général › Ouverture et arrière-plan,
activer « Jauge ».

## Avertissement : app non validée par Apple

Jauge est signée mais pas « notarisée » : cela demande un compte développeur payant. macOS la juge donc non
vérifiée au premier lancement. Le script retire pour cela le blocage du premier lancement (l'attribut de
quarantaine posé par le téléchargement), seulement sur `Jauge.app`. À ne lancer que si vous faites confiance à
l'auteur ; le script se lit en entier : [installer.sh](installer.sh).

## Mettre à jour

Dans l'app : fenêtre Jauge › Réglages › Mises à jour (vérification au démarrage puis une fois par jour, bouton
« Installer la mise à jour »). Ou relancer la commande ci-dessus.

## Désinstaller

Télécharger le zip de la dernière version dans les [Releases](../../releases/latest), le décompresser, puis lancer
`./uninstall.sh` dans le dossier `Jauge-X.Y.Z` : le service s'arrête (la charge redevient celle de macOS), l'app est
supprimée, et le script demande avant d'effacer l'historique.

## Envoyer un rapport de test

```
~/Applications/Jauge.app/Contents/MacOS/Jauge --ctl rapport --fichier
```

Un fichier Markdown est écrit sur le Bureau : modèle du Mac, puce, macOS, clés de charge détectées, état de la
batterie. Ni nom, ni numéro de série. À envoyer à Lucas.
