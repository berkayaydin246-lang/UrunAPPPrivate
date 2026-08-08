# Etiketly Puanı: Kamuya Açık Metodoloji Özeti

Status: consumer-facing source draft, **not yet a published legal page**.

## Etiketly Puanı Nedir?

Etiketly Puanı, ürünün doğrulanmış besin ve içerik verilerinden,
Etiketly'nin sürümlü ve deterministik metodolojisiyle hesaplanan 0-100 arası
bir içerik profili göstergesidir.

Puan bir sağlık veya güvenlik puanı değildir. Tıbbi tanı, hastalık riski
olasılığı, kişisel beslenme önerisi, ürün güvenliği sertifikası, resmi onay ya
da üretici desteği anlamına gelmez.

**COUNSEL REVIEW REQUIRED:** “Etiketly Puanı” ve “İçerik profili:
Çok iyi/İyi/Orta/Zayıf/Çok zayıf” ifadelerinin bağımsız üçüncü taraf uygulamada
Türk beslenme/sağlık beyanı ve reklam kuralları bakımından kullanımı.

## Hangi Veriler Kullanılır?

- Ambalajdan veya güvenilir ürün kaynağından alınan 100 g/100 ml besin değerleri.
- Puanlama kategorisi ve gerekli ürün durumu/bileşim kanıtları.
- Doğrulanmış içerik listesi ve eşleştirilen katkı değerlendirmeleri.
- Her girdinin kaynak ve doğrulama durumu.

Kullanıcı oyu, üretici talebi ve yapay zeka kararı sayısal puanı belirlemez.
Yapay zeka/OCR yalnız veri çıkarımı adayı üretebilir; gerekli kanıt admin
doğrulamasından geçmeden puana yetki vermez.

## Hesaplama

Etiketly Puanı metodolojisi v1:

```text
Etiketly Puanı =
  %80 × beslenme bileşeni
  +
  %20 × katkı bileşeni
```

Her iki bileşen 0-100 aralığındadır. Sonuç 0-100 aralığında gösterilir. Bu
özet, beslenme bileşenini “resmi Nutri-Score” olarak adlandırmaz. Etiketly,
Nutri-Score logosu veya A-E notu kullanmaz ve resmi ilişki ima etmez.

Puan bantları değişmeden şöyledir:

| Puan | Kamusal bağlam |
|---|---|
| 80-100 | İçerik profili: Çok iyi |
| 60-79 | İçerik profili: İyi |
| 40-59 | İçerik profili: Orta |
| 20-39 | İçerik profili: Zayıf |
| 0-19 | İçerik profili: Çok zayıf |

## Puan Ne Zaman Gösterilmez?

Gerekli besin değerleri, ölçüm temeli, kategori/bileşim kanıtı, içerik
tamlığı veya katkı eşleştirmesi yeterince doğrulanmadığında puan üretilmez.
Eksik veri için tahmini bir sayı gösterilmez.

## Veriler Ve Puan Değişebilir

Ürün reçetesi, ambalaj, besin değerleri, kaynak kanıtı veya sürümlü metodoloji
değiştiğinde puan yeniden hesaplanabilir ve değişebilir. Özellikle içerik ve
alerjen gereksinimleri için her zaman güncel fiziksel ambalaj kontrol edilmelidir.

## Düzeltmeler

Ürün detayındaki “Ürün verisinde hata mı var?” yolu kullanılarak kaynak veya
ürün verisi bildirilebilir. Bildirimler incelemeye alınır; doğrudan ürün verisini
ya da puanı değiştirmez. Kanıtlanan veri düzeltmesi uygulandıktan sonra puan aynı
metodolojiyle otomatik yeniden hesaplanır. Puan şirket veya kullanıcıyla pazarlık
edilmez.

## Bağımsızlık

- Üreticiler daha yüksek puan satın alamaz veya formülü kendilerine özel
  değiştiremez.
- Gelecekte reklam/sponsorluk olursa açıkça etiketlenir; puan girdisini,
  formülü veya organik sıralamayı etkileyemez.
- Aynı metodoloji sürümü ve aynı doğrulanmış girdiler aynı sonucu üretir.

Bu maddeler gelecekteki ticari modele ilişkin yayın politikasıdır; Etiketly'nin
geçmişte hiç ticari ilişki kurmadığına dair doğrulanmamış bir tarihsel iddia
değildir.

## Bilgilendirme Sınırı

Etiketly yalnız bilgilendirme amaçlıdır; tıbbi cihaz değildir ve herhangi bir
durumu teşhis, tedavi, iyileştirme veya önleme amacı taşımaz. Puan
kişiselleştirilmiş tıbbi ya da diyetetik tavsiye değildir. Tıbbi, beslenme veya
alerji gereksinimleri olan kullanıcılar güncel ambalaja ve gerektiğinde yetkin
bir sağlık uzmanına başvurmalıdır.

## Sürümler

Metodoloji değişiklikleri sürümlenir ve önemli değişiklikler yayın notuyla
açıklanır. Ayrıntılı politika:
[SCORING_CHANGE_POLICY.md](./SCORING_CHANGE_POLICY.md).
