#!/bin/bash
# check-branding-regressions.sh
# Verhindert, dass alte Mapflow-Bilder durch fehlerhafte Merges zurückkehren.

# Liste bekannter Mapflow-Bild-Hashes (git blob SHAs)
FORBIDDEN_HASHES=(
    "e36e92c00e58847b72ab8aa2247740cb6baa08c3" # MapFlow_Logo_HQ-Full-L.png
    "cc155d0feace6429513aabacf76b9fee3454c201" # MapFlow_Logo_HQ-Full-L.webp
    "92658981ac88bd2f28fa50f1a07c1569626f349f" # MapFlow_Logo_HQ-Full-M.png
    "a57d021f55fdaee8689ef6c1486d4152630bd69c" # MapFlow_Logo_HQ-Full-M.webp
    "abb54fea8b98cdcc902822676694a64a02bbd2e1" # MapFlow_Logo_LQ-Full.icns
    "8458fe2c2a9e765fb69c901698ebdb6814269455" # MapFlow_Logo_LQ-Full.ico
    "55ea17ab81f6ee0604e2bf91848a1ecd39ba6550" # mapflow.icns
    "d005738c1ed35077f3280199d2e060d79a35c01e" # mapflow.ico
    "f5472fdeda410c83130f3d34dcc0b0e52f078fbd" # mapflow.png
)

echo "🔍 Suche nach Branding-Regressionen (alte Mapflow-Inhalte)..."
FOUND_ISSUES=0

# Alle Dateien im Repository prüfen
while read -r line; do
    mode=$(echo "$line" | awk '{print $1}')
    type=$(echo "$line" | awk '{print $2}')
    hash=$(echo "$line" | awk '{print $3}')
    path=$(echo "$line" | awk '{print $4}')

    for forbidden in "${FORBIDDEN_HASHES[@]}"; do
        if [ "$hash" == "$forbidden" ]; then
            echo "❌ FEHLER: Veralteter Mapflow-Inhalt gefunden in: $path"
            echo "   (Hash: $hash)"
            FOUND_ISSUES=$((FOUND_ISSUES + 1))
        fi
    done
done < <(git ls-tree -r HEAD)

if [ $FOUND_ISSUES -gt 0 ]; then
    echo ""
    echo "⚠️  REGRESSION ENTDECKT! Insgesamt $FOUND_ISSUES veraltete Dateien gefunden."
    echo "Bitte die korrekten Vorce-Branding-Assets wiederherstellen."
    exit 1
else
    echo "✅ Kein altes Branding gefunden. Alles sauber."
    exit 0
fi
