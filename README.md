# Supervision
## Backup jobs
Ce script permet de surveiller les tâches de sauvegarde dans Veeam Backup & Replication et d'envoyer des alertes basées sur le statut des sauvegardes. Il analyse les sessions récentes en fonction de l'heure définie par le paramètre `$RPO`, en signalant toute session ayant échoué, étant en avertissement ou en échec. L'objectif est d'assurer un suivi efficace des sauvegardes et de signaler rapidement tout problème éventuel nécessitant une attention particulière.
