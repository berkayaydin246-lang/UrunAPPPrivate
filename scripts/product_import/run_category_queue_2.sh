#!/usr/bin/env bash
set -u

cd ~/food_analyzer_app || exit 1

set -a
source .env
set +a

LOG_DIR="scripts/product_import/output/category_queue_logs_2"
mkdir -p "$LOG_DIR"

MASTER_SUMMARY="$LOG_DIR/_summary_$(date +%Y%m%d_%H%M%S).log"

echo "========================================" | tee -a "$MASTER_SUMMARY"
echo "Kategori kuyruğu 2 başladı: $(date)" | tee -a "$MASTER_SUMMARY"
echo "Log klasörü: $LOG_DIR" | tee -a "$MASTER_SUMMARY"
echo "========================================" | tee -a "$MASTER_SUMMARY"

CATEGORIES=(
  "sekerleme 500"
  "kek 500"
  "cikolata 500"
  "bar_kaplamalilar 500"
  "kraker 500"
  "misir_ve_pirinc_patlagi 500"
  "kuru_meyve 500"
  "sakiz 500"
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
echo "Tüm kategori kuyruğu 2 bitti: $(date)" | tee -a "$MASTER_SUMMARY"
echo "========================================" | tee -a "$MASTER_SUMMARY"
