# Publier le site Convergence Suite

Le site est isolé dans `website/`. Le workflow standard Jekyll reçoit ce dossier comme source et publie le résultat produit dans `_site/`.

## 1. Prévisualiser avec Jekyll

Avec Ruby 3.3 et Bundler installés :

```sh
cd website
bundle install
bundle exec jekyll serve
```

Ouvrez [la prévisualisation locale](http://localhost:4000/convergence-suite/). Pour compiler sans serveur, exécutez `JEKYLL_ENV=production bundle exec jekyll build`.

## 2. Activer Pages et publier

1. Dans **Settings → Pages → Build and deployment**, sélectionnez **GitHub Actions** comme **Source**. Un administrateur du dépôt peut effectuer ce réglage.
2. Proposez vos modifications dans une pull request vers `main`. Le workflow compile les modifications du site sur la PR.
3. Après fusion, le push sur `main` déclenche la publication. Vous pouvez aussi relancer le workflow depuis **Actions → Deploy Jekyll with GitHub Pages dependencies preinstalled → Run workflow**, sur `main`.
4. Vérifiez le succès du job **deploy**, puis ouvrez [le site GitHub Pages](https://devdownin.github.io/convergence-suite/).

## 3. Configurer un domaine personnalisé

Pour un sous-domaine comme `suite.example.com`, saisissez-le dans **Settings → Pages → Custom domain**. Chez votre fournisseur DNS, créez un enregistrement **CNAME** de `suite.example.com` vers `devdownin.github.io`. Pour un domaine racine, utilisez les enregistrements indiqués dans la documentation GitHub.

Si le site est servi à la racine du domaine, utilisez `url: https://suite.example.com` et `baseurl: ""` dans `website/_config.yml`, puis redéployez. Activez **Enforce HTTPS** une fois le domaine validé. Avec GitHub Actions, le réglage **Custom domain** et le DNS commandent le domaine. GitHub ignore le fichier `CNAME` du dépôt dans ce mode de publication.

- [Workflow Jekyll standard](https://github.com/actions/starter-workflows/blob/main/pages/jekyll-gh-pages.yml)
- [Configurer la source de publication](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)
- [Gérer un domaine personnalisé](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)
