# Zabbix 8.0 LTS na FreeBSD 14.3

![FreeBSD server s monitoringem](Images/freebsd-zabbix8-hero.png)

Reprodukovatelná školní instalace Zabbix serveru 8.0 LTS, MariaDB, webového rozhraní přes Apache 2.4 a klasického agenta na boxu `bento/freebsd-14.3`. Web běží na **http://127.0.0.1:8080/**. Virtuální stroj má 2 CPU a 4 GB RAM; paměť je vyšší než minimum zadání kvůli sestavení portu Zabbix serveru.

## Spuštění

Požadavky: Vagrant, VirtualBox, internet a alespoň 4 GB volné RAM pro VM. V kořeni projektu:

```sh
vagrant validate
vagrant up
vagrant ssh
```

Provisioning běží automaticky. Je možné ho zopakovat příkazem `vagrant provision`; již existující databáze se znovu neimportuje. První spuštění trvá déle kvůli sestavení Zabbix serveru. Skript končí při chybě nenulovým kódem.

Pomocné skripty a export se před instalací nahrají do VM pomocí Vagrant `file` provisionerů. Instalace tak nepotřebuje sdílenou složku `/vagrant`. Pokud provisioning skončí po instalaci balíčků, spusťte po opravě `vagrant provision`; není nutné VM zničit.

## Instalace

Skript nastaví oficiální FreeBSD `latest` repozitář a běžné závislosti včetně `apache24` a `mod_php84` instaluje jako binární balíčky přes `pkg`. PHP obsluhuje Apache přímo přes modul; PHP-FPM není potřeba. Používá porty FreeBSD 8.0 pro server, agenta a frontend. Zabbix server sestaví z portu s podporou MariaDB 11.4; agent a frontend vezme z `pkg`, pokud jsou v `latest` dostupné, jinak z portů. Frontend je pouze kopírování PHP souborů, bez kompilace. Instalace se inspiruje [postupem pro Zabbix 8 agenta na FreeBSD](https://github.com/sposdknl/smejdil-osy-2026-zbx8-auto-reg).

MariaDB má databázi `zabbix` s `utf8mb4` a samostatným účtem omezeným na tuto databázi. Heslo databáze se generuje ve VM do `/var/db/zabbix-install/db-password` s oprávněním pouze pro root. Konfigurace serveru a frontendu vzniká až ve VM; v Git nejsou žádná hesla. Výchozí účet Zabbix `Admin` se při prvním provisioningu přenastaví na náhodné heslo uložené ve VM do `/var/db/zabbix-install/admin-password`.

Heslo pro přihlášení zobrazíte ve VM:

```sh
sudo cat /var/db/zabbix-install/admin-password
```

Přihlaste se na http://127.0.0.1:8080/ jako `Admin`. Web má v záhlaví jméno **SmEjDiL · FreeBSD 14.3 · Zabbix 8**; PHP wizard se neprochází. Web je dostupný jen z hostitelského `127.0.0.1`. SSH používá `vagrant ssh` (přesměrovaný port 2211 také jen na loopbacku).

## Monitoring a ověření

Provisioning přes Zabbix API založí skupinu `SPOS Lab`, importuje upravený export `Zabbix/export/sposdk.cz_hosts.yaml` a připraví dva hosty:

| Host | Kontrola |
| --- | --- |
| `spos-zabbix8` | šablona `FreeBSD by Zabbix agent`, lokální agent na `127.0.0.1:10050` |
| `sposdk.cz` | položka `sposdk.cert.days`, počet dnů do konce platnosti TLS certifikátu `https://sposdk.cz` |

FreeBSD port Zabbix 8 obsahuje klasického agenta. Pro kontrolu certifikátu proto používáme krátký skript s `openssl` a vlastní položku agenta. Agent 2 a jeho šablona `Website certificate by Zabbix agent 2` nejsou součástí dostupného FreeBSD portu. Původní export pro Zabbix 7 používal šablonu Agenta 2. Upravený export pro Zabbix 8 vytváří hosta `sposdk.cz` ve skupině `Web Certificate`; vlastní položka klasického agenta se následně doplní přes API. Import se provede pouze tehdy, když host ještě neexistuje.

Po dokončení `vagrant up` ověřte:

```sh
vagrant ssh
sudo service mysql-server status
sudo service zabbix_server status
sudo service zabbix_agentd status
sudo service apache24 status
/usr/local/sbin/zabbix_server -V
/usr/local/sbin/zabbix_agentd -V
/usr/local/sbin/zabbix_agentd -t sposdk.cert.days
```

Ve webu otevřete **Monitoring → Latest data** a vyberte hosty `spos-zabbix8` a `sposdk.cz`. Položka certifikátu má interval 1 hodinu, první údaj se objeví po prvním sběru. Po vlastním spuštění VM doplňte do `Images/` skutečné snímky webu, hostů, dat a služeb; titulní ilustrace není důkaz běhu.

## Řešení potíží

- Chyba při `pkg` nebo `git clone`: ověřte DNS a síť VM, pak spusťte `vagrant provision`.
- Neúspěšné sestavení portu: zkontrolujte `/usr/ports/net-mgmt/zabbix8-server`, volné místo a výpis chyby. Opakované `vagrant provision` bezpečně naváže.
- Web není dostupný: `sudo service apache24 status`, `sudo apachectl configtest` a `sudo apachectl -M | grep php_module`.
- Agent nebo server neběží: zkontrolujte `/var/log/zabbix/` a nastavení služeb přes `sysrc`.
- `sposdk.cert.days` je unsupported: ověřte přístup VM k `sposdk.cz:443` a spusťte `/usr/local/libexec/zabbix/sposdk-cert-days.sh`.

## Zdroje

- [FreeBSD port Zabbix 8 server](https://www.freshports.org/net-mgmt/zabbix8-server/)
- [FreeBSD port Zabbix 8 agent](https://www.freshports.org/net-mgmt/zabbix8-agent/)
- [Zabbix 8 dokumentace](https://www.zabbix.com/documentation/8.0/en/)
