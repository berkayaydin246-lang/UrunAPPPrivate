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
  echo "Key değerlerini terminale/chate yazdırma."
  exit 1
fi

RUN_ID="$(date +%Y%m%d_%H%M%S)"
LOG_DIR="scripts/product_import/output/selected_missing_plus_tested_${RUN_ID}"
MASTER_LOG="$LOG_DIR/_master.log"

mkdir -p "$LOG_DIR"

# SQL çıktındaki CEK kategorileri + test için az çekilmiş ATLA kategorileri.
CATEGORIES=(
  bakliyat
  bebek_atistirmalik
  bebek_beslenme
  bebek_icecegi

  cay
  kahve
  maden_suyu
  meyve_suyu

  dondurulmus_borek
  dondurulmus_firin_urunleri
  dondurulmus_hazir_yemek
  dondurulmus_manti
  dondurulmus_meyve
  dondurulmus_patates
  dondurulmus_pizza
  dondurulmus_sebze
  dondurulmus_sushi
  dondurulmus_tatli

  ekmek
  galeta_grissini_gevrek
  hamur_pasta_malzemeleri
  hazir_manti
  kuru_pasta

  makarna
  meze
  ozel_beslenme_urunleri
  paketli_sandvic
  pasta
  pide_lahmacun
  pratik_yemek

  sivi_yag
  tatli
  tek_dondurma
  kap_dondurma
  tuz_baharat_harc
  zeytin
)

echo "========================================" | tee -a "$MASTER_LOG"
echo "Etiketly selected Migros import başladı" | tee -a "$MASTER_LOG"
echo "Run ID: $RUN_ID" | tee -a "$MASTER_LOG"
echo "Log dir: $LOG_DIR" | tee -a "$MASTER_LOG"
echo "Başlangıç: $(date)" | tee -a "$MASTER_LOG"
echo "Kategori sayısı: ${#CATEGORIES[@]}" | tee -a "$MASTER_LOG"
echo "========================================" | tee -a "$MASTER_LOG"

echo "" | tee -a "$MASTER_LOG"
echo "YAML kategori kontrolü..." | tee -a "$MASTER_LOG"

MISSING_IN_YAML=0
for CATEGORY in "${CATEGORIES[@]}"; do
  if ! grep -qE "category:[[:space:]]*$CATEGORY$" data/web_product_sources.yaml; then
    echo "YAML'DE YOK: $CATEGORY" | tee -a "$MASTER_LOG"
    MISSING_IN_YAML=1
  fi
done

if [ "$MISSING_IN_YAML" -ne 0 ]; then
  echo "" | tee -a "$MASTER_LOG"
  echo "ERROR: Bazı kategoriler data/web_product_sources.yaml içinde yok. Önce YAML'i düzelt." | tee -a "$MASTER_LOG"
  exit 1
fi

echo "YAML kontrol OK." | tee -a "$MASTER_LOG"

FAILED=()

for CATEGORY in "${CATEGORIES[@]}"; do
  LOG_FILE="$LOG_DIR/${CATEGORY}.log"

  echo "" | tee -a "$MASTER_LOG"
  echo "----------------------------------------" | tee -a "$MASTER_LOG"
  echo "BAŞLIYOR: $CATEGORY | limit=500 | $(date)" | tee -a "$MASTER_LOG"
  echo "LOG: $LOG_FILE" | tee -a "$MASTER_LOG"
  echo "----------------------------------------" | tee -a "$MASTER_LOG"

  python3 scripts/product_import/scrape_products_from_web.py \
    --source migros \
    --category "$CATEGORY" \
    --limit 500 \
    --real \
    --auto-approve-high-quality \
    --auto-approve-min-score 100 \
    2>&1 | tee "$LOG_FILE"

  EXIT_CODE=${PIPESTATUS[0]}

  echo "" | tee -a "$MASTER_LOG"
  echo "BİTTİ: $CATEGORY | exit_code=$EXIT_CODE | $(date)" | tee -a "$MASTER_LOG"
  echo "Son 25 satır:" | tee -a "$MASTER_LOG"
  tail -n 25 "$LOG_FILE" | tee -a "$MASTER_LOG"

  if [ "$EXIT_CODE" -ne 0 ]; then
    FAILED+=("$CATEGORY")
    echo "UYARI: $CATEGORY hata verdi, kuyruk devam ediyor." | tee -a "$MASTER_LOG"
  fi

  echo "30 saniye bekleniyor..." | tee -a "$MASTER_LOG"
  sleep 30
done

echo "" | tee -a "$MASTER_LOG"
echo "========================================" | tee -a "$MASTER_LOG"
echo "Selected Migros import bitti: $(date)" | tee -a "$MASTER_LOG"

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "Hata veren kategoriler:" | tee -a "$MASTER_LOG"
  printf '%s\n' "${FAILED[@]}" | tee -a "$MASTER_LOG"
else
  echo "Hata veren kategori yok." | tee -a "$MASTER_LOG"
fi

echo "========================================" | tee -a "$MASTER_LOG"
