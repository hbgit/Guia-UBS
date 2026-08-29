-- `asset` passa a guardar o ARQUIVO, e nao so o metadado dele.
--
-- Anulavel de proposito: `asset` e o primeiro de tudo que se cadastra (oito
-- tabelas apontam para ele), e exigir os bytes na criacao travaria a autoria
-- inteira ate o designer entregar o arquivo. Quem RECUSA publicar sem binario e
-- o packer, que e quem assina.
--
-- Uma linha so, sem recriacao de tabela: `sha256` e `bytes` ganharam
-- `$defaultFn` e nao `.default()`, justamente para o drizzle-kit nao emitir
-- `CREATE TABLE __new_asset; DROP TABLE asset` num pai de FK de oito tabelas que
-- ainda carrega o gatilho `asset_version_monotonic`.
--
-- Expandir e contrair vao SEPARADAS (a contracao e a 0007) porque uma coluna
-- saindo e outra entrando na mesma tabela fazem o drizzle-kit perguntar,
-- interativamente, se aquilo e um rename — e sem TTY ele simplesmente morre.

ALTER TABLE `asset` ADD `binary` blob;
