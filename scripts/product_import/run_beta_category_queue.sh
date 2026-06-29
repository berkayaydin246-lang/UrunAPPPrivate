#!/usr/bin/env bash
set -uo pipefail

cd ~/food_analyzer_app || exit 1

if [ -f .env ]; then
  set -a
  source .env
  set +a
else
  echo "ERROR: .env bulunamadı."
  exit 1
fi

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_SERVICE_KEY:-}" ]; then
  echo "ERROR: SUPABASE_URL ve SUPABASE_SERVICE_KEY .env içinde olmalı."
  echo "Not: Key değerlerini terminale veya chate yazdırma."
  exit 1
fi

LOG_DIR="scripts/product_import/output/category_queue_logs"
mkdir -p "$LOG_DIR"

MASTER_SUMMARY="$LOG_DIR/_beta_summary_$(date +%Y%m%d_%H%M%S).log"

echo "========================================" | tee -a "$MASTER_SUMMARY"
echo "Etiketly beta kategori kuyruğu başladı: $(date)" | tee -a "$MASTER_SUMMARY"
echo "Log klasörü: $LOG_DIR" | tee -a "$MASTER_SUMMARY"
echo "========================================" | tee -a "$MASTER_SUMMARY"

# Format:
# "kategori_adi limit"
#
# Kategori adları data/web_product_sources.yaml içindeki category isimleriyle aynı olmalı.
CATEGORIES=(
  "makarna 500"
  "bakliyat 500"
  "sivi_yag 500"
  "tuz_baharat_harc 500"
  "hamur_pasta_malzemeleri 500"
  "ozel_beslenme_urunleri 500"

  "cay 500"
  "maden_suyu 500"
  "meyve_suyu 500"
  "kahve 500"

  "zeytin 500"

  "ekmek 500"
  "kuru_pasta 500"
  "galeta_grissini_gevrek 500"
  "tatli 500"
  "pasta 500"

  "pratik_yemek 500"
  "meze 500"
  "hazir_manti 500"
  "paketli_sandvic 500"

  "dondurulmus_pizza 500"
  "dondurulmus_patates 500"
  "dondurulmus_sebze 500"
  "dondurulmus_sushi 500"
  "dondurulmus_meyve 500"
  "dondurulmus_borek 500"
  "dondurulmus_manti 500"
  "pide_lahmacun 500"
  "dondurulmus_tatli 500"
  "dondurulmus_firin_urunleri 500"
  "dondurulmus_hazir_yemek 500"

  "kap_dondurma 500"
  "tek_dondurma 500"

  "bebek_beslenme 500"
  "bebek_icecegi 500"
  "bebek_atistirmalik 500"
)

for item in "${CATEGORIES[@]}"; do
  CATEGORY="$(echo "$item" | awk '{print $1}')"
  LIMIT="$(echo "$item" | awk '{print $2}')"

  LOG_FILE="$LOG_DIR/${CATEGORY}_$(date +%Y%m%d_%H%M%S).log"

  echo "" | tee -a "$MASTER_SUMMARY"
  echo "----------------------------------------" | tee -a "$MASTER_SUMMARY"
  echo "Başlıyor: $CATEGORY | limit=$LIMIT | $(date)" | tee -a "$MASTER_SUMMARY"
  echo "Log: $LOG_FILE" | tee -a "$MASTER_SUMMARY"
  echo "----------------------------------------" | tee -a "$MASTER_SUMMARY"

  python3 scripts/product_import/scrape_products_from_web.py \
    --source migros \
    --category "$CATEGORY" \
    --limit "$LIMIT" \
    --real \
    --auto-approve-high-quality \
    --auto-approve-min-score 100 \
    2>&1 | tee "$LOG_FILE"

  EXIT_CODE=${PIPESTATUS[0]}

  echo "" | tee -a "$MASTER_SUMMARY"
  echo "Bitti: $CATEGORY | exit_code=$EXIT_CODE | $(date)" | tee -a "$MASTER_SUMMARY"
  echo "Son özet:" | tee -a "$MASTER_SUMMARY"
  tail -n 25 "$LOG_FILE" | tee -a "$MASTER_SUMMARY"

  if [ "$EXIT_CODE" -ne 0 ]; then
    echo "HATA: $CATEGORY import sırasında hata verdi. Kuyruk durduruldu." | tee -a "$MASTER_SUMMARY"
    echo "Log dosyası: $LOG_FILE" | tee -a "$MASTER_SUMMARY"
    exit "$EXIT_CODE"
  fi

  echo "45 saniye bekleniyor..." | tee -a "$MASTER_SUMMARY"
  sleep 45
done

echo "" | tee -a "$MASTER_SUMMARY"
echo "========================================" | tee -a "$MASTER_SUMMARY"
echo "Tüm beta kategori kuyruğu bitti: $(date)" | tee -a "$MASTER_SUMMARY"
echo "========================================" | tee -a "$MASTER_SUMMARY"
