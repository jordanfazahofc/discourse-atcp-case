# frozen_string_literal: true

# Saat flag lampiran kasus aktif (Internal + tipe "atcp-case-attachment"),
# validasi ekstensi dan ukuran memakai setting plugin kasus. Selain itu
# perilaku default core tidak berubah.
module Atcp
  module CaseUploadValidatorPatch
    private

    def authorized_extensions(upload)
      return super unless Thread.current[:atcp_case_upload]

      extensions_to_set(SiteSetting.atcp_case_attachment_extensions)
    end

    def maximum_file_size(upload, type)
      return super unless Thread.current[:atcp_case_upload]
      return if !upload.validate_file_size

      max_size_bytes = SiteSetting.atcp_case_max_attachment_mb.to_i.megabytes
      return if upload.filesize <= max_size_bytes

      upload.errors.add(
        :filesize,
        I18n.t(
          "upload.#{type}s.too_large_humanized",
          max_size:
            ActiveSupport::NumberHelper.number_to_human_size(max_size_bytes)
        )
      )
    end
  end
end
