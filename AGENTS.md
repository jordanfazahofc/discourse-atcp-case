# discourse-atcp-case

1. Repo: https://github.com/jordanfazahofc/discourse-atcp-case (public, branch main). Commit dan push hanya dari DALAM folder plugin ini. Setelah push, `git rev-parse HEAD` harus sama dengan `git ls-remote` ke repo di atas.
2. Rollback migrasi plugin: `LOAD_PLUGINS=1 bin/rails db:migrate:down VERSION=<versi>`. Jangan pakai `db:rollback` (task itu tidak memuat `load_config` di fork ini, dan core tidak diubah).
3. `bin/lint`, `bin/rspec`, dan `bin/qunit` dijalankan dari ROOT repo dengan path `plugins/discourse-atcp-case/...`.
4. Plugin ini dimuat SEBELUM core. Jangan merujuk `Atcp::InternalAccess` atau `Atcp::InternalAccessGuard` saat boot atau di body class. Rujukan hanya di dalam method yang dipanggil saat request, atau lewat `require_relative` dengan `unless defined?` seperti announcement/plugin.rb:40-47.
5. Label UI dan nilai pilihan berbahasa Inggris. Nilai konstanta ada di `app/models/atcp_case.rb`.
6. Tanpa git write oleh agen (add, commit, push dilakukan oleh pemilik repo).
