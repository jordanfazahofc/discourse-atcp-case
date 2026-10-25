# frozen_string_literal: true

# Aging dan waiting adalah nilai turunan (bukan kolom) yang dipakai serializer
# daftar dan detail kasus. Dipisah dari serializer supaya bisa dites sendiri.
module AtcpCaseTiming
  SECONDS_PER_DAY = 86_400

  module_function

  # Selisih hari antara opened_at dan closed_at (atau sekarang), dibulatkan
  # ke bawah.
  def aging_days(atcp_case, now: Time.zone.now)
    ((atcp_case.closed_at || now) - atcp_case.opened_at).to_i / SECONDS_PER_DAY
  end

  # Waiting adalah label entri pengguna (bukan sistem) TERAKHIR bila labelnya
  # diawali "Waiting for" dan kasus belum Closed. Akumulasi lama per label
  # ditunda ke Fase 4.
  def waiting(atcp_case, now: Time.zone.now)
    return nil if atcp_case.status == "Closed"

    last_user_update =
      atcp_case.atcp_case_updates.reject(&:is_system).max_by(&:created_at)
    return nil if last_user_update.nil?
    unless last_user_update.update_type.to_s.strip.match?(/\Awaiting for/i)
      return nil
    end

    {
      label: last_user_update.update_type,
      since: last_user_update.created_at,
      days: (now - last_user_update.created_at).to_i / SECONDS_PER_DAY
    }
  end
end
