# frozen_string_literal: true

# Dipakai CaseUpdatesController saat unique index menolak upload yang
# sudah terpasang di kasus lain (jalur constraint DB). Error khusus
# (bukan ActiveRecord::Rollback) supaya transaksi savepoint benar-benar
# di-ROLLBACK dan koneksi tidak tinggal dalam kondisi aborted.
class AtcpCaseUpdateDuplicateAttachmentError < StandardError
  attr_reader :upload

  def initialize(upload)
    @upload = upload
    super("attachment already used")
  end
end
