# myblitzaudit-examples

Real output from [myblitzaudit](https://github.com/emerichunter/myblitzaudit-collect),
not a mock-up. The bundle in `bundle/` was collected from a live MySQL 8.0
instance; the HTML in `reports/` is what the engine produced from that bundle.

Open any file in `reports/` in a browser. No server, no build step, no network.

---

## Reports

| File | Database | What it is |
|---|---|---|
| `reports/offline_ultimate_report_shopdb.html` | shopdb | Comprehensive audit — 29 sections: inventory, indexes, foreign keys, security, replication, InnoDB health, top digests, configuration |
| `reports/offline_perf_report_shopdb.html` | shopdb | Performance deep-dive — waits, locks, temp tables, buffer pool, slow digests |
| `reports/offline_ultimate_report_support.html` | support | Same audit on a second database, utf8mb3 and blob-heavy |
| `reports/offline_perf_report_support.html` | support | Same deep-dive on the second database |

Both HTML files are self-contained: inline CSS, no webfonts, no external
requests. They render identically on an air-gapped machine.

---

## The bundle

`bundle/` is the input that produced those reports:

```text
bundle/
  global_snapshot.json        users, grants, variables, status, replication
  catalog_db_shopdb.json      schema metadata
  catalog_db_support.json
  stat_db_shopdb.json         performance counters and digests
  stat_db_support.json
  schema_dump_shopdb.sql      DDL only
  schema_dump_support.sql
  manifest.json
```

Read them. That is the whole point of publishing this: you can see exactly what
crosses the boundary before you run the collector on your own server. There is
no row data in any file. Password hashes are never selected.

## The demo schema

`demo/plant_issues.sql` recreates the database these reports describe. It is a
museum of bad practice on purpose, so every finding in the reports has a cause
you can look at:

- `product_views` has no primary key.
- `legacy_audit` is MyISAM.
- `orders.customer_id` has a foreign key and no supporting index.
- `order_items` carries a redundant single-column index next to its composite PK.
- `sessions` has an index nobody uses and a duplicate of the primary key.
- `newsletter.address` is latin1 inside an utf8mb4 database.
- `support` is utf8mb3, which cannot store emoji.
- `reporting`@`%` has an empty password; `app`@`%` holds `ALL PRIVILEGES` from anywhere.

Reproduce end to end:

```bash
docker run -d --name blitz-demo -e MYSQL_ROOT_PASSWORD=demopass mysql:8.0
docker exec -i blitz-demo mysql -uroot -pdemopass < demo/plant_issues.sql
./my_collect.sh --docker-container blitz-demo --user root --password demopass
```

Then replay the bundle with the engine to get these reports back.

---

## License

MIT for the sample bundle, the reports and the demo schema. See [LICENSE](LICENSE).
The engine that produced the reports is proprietary and not included here.
