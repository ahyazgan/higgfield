> ℹ️ **Bu dosya insan-okunur senaryodur (anlatı).** Teknik **tek doğru kaynak**
> `missions.json` + `presets/`'tir; scriptler yalnızca onları okur. Üretimi
> etkileyen bir değişiklik yapacaksan bu dosyayı değil, JSON'ları düzenle —
> böylece iki nüsha birbirinden kaymaz.

# NORTH — Mission 01: Senaryo (GTA Third-Person Kamera)

> 6 sahnelik bir sekans. Karakter (Jay) hep **arkadan**, hep takip ediliyor.
> İki şey her sahnede **sabit** kalmalı: **karakter** (Soul ID) ve **bina** (NORTH_MASTER referans görseli).

---

## 🔒 Sabit Bloklar (her promptta aynen kullanılır)

### KARAKTER BLOĞU
```
young Mediterranean man, 22-24 years old,
short black hair clean fade haircut,
thick black eyebrows, light 3-day stubble with small mustache,
olive-tan skin, lean build,
wearing fitted white cotton t-shirt,
black canvas chef apron tied at waist (straps crossing on back),
dark navy slim-fit jeans,
black low-top sneakers,
silver watch on left wrist,
```

### KAMERA BLOĞU (GTA)
```
GTA V THIRD PERSON GAMEPLAY CAMERA,
camera positioned directly behind character,
camera floating 2-3 meters behind at 1.7m height,
camera angled slightly downward following character,
character seen from BEHIND, back visible,
character positioned lower-center or left-third of frame,
wide angle lens showing environment ahead of character,
video game third person perspective like GTA V gameplay,
NOT selfie, NOT portrait, NOT front-facing,
character's face NOT toward camera,
```

### BİNA TUTARLILIK BLOĞU (referans yüklendiğinde)
```
same exact NORTH restaurant building as reference image,
identical brick, identical door, identical sign,
do not change the building,
```

### KALİTE / STİL BLOĞU
```
shot on iPhone 15 Pro Max,
natural golden hour light, slight grain,
candid documentary style, no filters,
NOT cinematic grade, NOT studio,
NOT illustration, NOT cartoon, NOT render,
hyperrealistic, real phone snapshot, authentic moment
```

---

## 🛠️ Tutarlılık Yöntemi — İki Seçenek (her sahnede geçerli)

**Yöntem A — Çift Referans (önerilen, akıcı):**
1. Soul ID → karakter (Jay)
2. NORTH_MASTER görseli → mekan/bina referansı (strength %70-75)
3. Prompt'ta binayı KELİMEYLE tarif etme; "same building as reference" yeter.

**Yöntem B — Inpaint (bina %100 sabit garantisi):**
1. NORTH_MASTER bina görselini al.
2. Binanın önündeki boş alanı maskele.
3. O alana sadece karakteri ekle: "young man in white t-shirt and apron, viewed from behind, GTA third person".
4. Bina hiç değişmez, sadece karakter eklenir.

> Dış sahnelerde (1-3) bina kritik → Yöntem A veya B.
> İç sahnelerde (4-6) bina değil iç mekan kritik → iç mekan master görseli ile aynı mantık.

---

## 🎬 SAHNELER

### SAHNE 1 — Sokakta Yürüyor (GTA açılış)
- **Aksiyon:** Karakter sokakta öne doğru yürüyor, rahat ve kendinden emin adım.
- **Kamera notu:** 3 metre arkada, 1.7m yükseklik, hafif aşağı.
- **Çerçeve:** Karakter alt-orta.
- **Mekan (önde açılan):** Dar Miami Little Havana sokağı, iki yanda eski kırmızı tuğla ve pastel binalar, arnavut kaldırımı, uzakta NORTH restoranı, park etmiş 1960'lar Amerikan arabaları, palmiyeler, üstte kablolar, altın saat ışığı.
- **Referans:** NORTH_MASTER (uzakta görünüyor) + Soul ID.

### SAHNE 2 — NORTH'a Yaklaşıyor
- **Aksiyon:** Karakter NORTH girişine doğru yürüyor, binaya yaklaşıyor.
- **Kamera notu:** 3 metre arkada, 1.7m, hafif aşağı.
- **Çerçeve:** Karakter alt-sol üçte bir.
- **Mekan:** NORTH kırmızı tuğla cephe önde, siyah ahşap 6 panelli kapı, kapı üstünde beyaz serif harflerle NORTH tabelası, içeride sıcak ışıklı büyük cam, kapının iki yanında terrakota saksı, arnavut kaldırımı.
- **Referans:** NORTH_MASTER (net, önde) + Soul ID. — **Yöntem A burada en kritik.**

### SAHNE 3 — Kapıyı Açıyor (etkileşim)
- **Aksiyon:** Karakter NORTH kapısında, sağ eli kapıyı itiyor, kapı içeri açılmaya başlıyor.
- **Kamera notu:** 2.5 metre arkada, 1.7m, hafif aşağı.
- **Çerçeve:** Karakter orta-sol.
- **Mekan:** Siyah ahşap kapı önde, pirinç kol, çevrede kırmızı tuğla, üstte NORTH tabelası, yanlarda terrakota saksılar, açılan kapıdan sıcak amber ışık sızıyor.
- **Referans:** NORTH_MASTER + Soul ID.

### SAHNE 4 — İçeri Giriyor (mekan geçişi)
- **Aksiyon:** Karakter boş restorana giriyor, içeri adım atıyor.
- **Kamera notu:** 2.5 metre arkada, 1.7m, karakteri içeri takip ediyor.
- **Çerçeve:** Karakter merkez.
- **Mekan (içeri):** Terk edilmiş boş restoran, yıpranmış açık kırmızı tuğla duvarlar, eski ahşap kirişli yüksek tavan, devrik masalar ve dağınık sandalyeler, öğleden sonra ışığında uçuşan toz, sağda altın ışık giren büyük pencere, arkada boş bar tezgahı.
- **Referans:** İÇ MEKAN MASTER (varsa) + Soul ID.

### SAHNE 5 — Mekanın Ortasında (geniş açı)
- **Aksiyon:** Karakter boş restoranın ortasında duruyor, etrafına bakıyor, kollar rahat.
- **Kamera notu:** 4 metre arkada, 2m yükseklik, aşağı açılı, ultra geniş.
- **Çerçeve:** Karakter alt-orta, geniş mekanda küçük.
- **Mekan:** Karakteri saran geniş terk edilmiş iç mekan, yüksek tavan + koyu ahşap kirişler, her yanda yıpranmış kırmızı tuğla, devrik masa/sandalyeler, sağ pencereden dramatik altın ışık huzmeleri, uçuşan toz, duvarda eski çerçeveli fotoğraflar, arkada boş bar tezgahı, ölçek ve boşluk hissi.
- **Referans:** İÇ MEKAN MASTER + Soul ID.

### SAHNE 6 — Duruyor, Karar (cutscene geçişi)
- **Aksiyon:** Karakter boş mekanın ortasında durur, önündeki odaya bakar, hafif baş hareketi, düşünceli duruş.
- **Kamera notu:** 2 metre arkada, 1.6m, yavaşça sağa kayıp üç-çeyrek arka görünüm. Başın arkası + çenenin hafif yanı görünür. ASLA tam yüz.
- **Çerçeve:** Karakter orta-sol.
- **Mekan:** Önde ve çevrede terk edilmiş restoran, kırmızı tuğla, ahşap kirişler, pencereden altın ışık, havada toz, potansiyel dolu boş mekan.
- **Referans:** İÇ MEKAN MASTER + Soul ID. — **Yöntem:** GTA V THIRD PERSON CUTSCENE CAMERA.

---

## 🔁 Döngü Kuralı (her Mission'da)
- Her sahne ARKADAN (third person), sırt görünür.
- Kamera 2-4 m arkada, 1.6-2 m yükseklikte.
- Karakter alt-orta veya sol-üçte bir, önde dünya açılıyor.
- ASLA selfie / portre / karşıdan.
- "GTA V third person gameplay camera" her promptta.
- Karakter sabit (Soul ID) + Mekan sabit (master referans görseli).

---

# NORTH — Mission 02: Hazırlık Sabahı

> Mission 01'in devamı. Jay restoranı restore etmiş, açılış sabahı.
> Hep arkadan, hep INTERIOR_MASTER + JAY_FACE referansı.

## 🎬 SAHNELER

### SAHNE 1 — Mutfak Girişi
- **Aksiyon:** Jay salondan mutfağa açılan çift kanat swing kapıdan içeri itiyor, iki kolu hafif kalkmış.
- **Kamera:** 2.5 m arkada, 1.7 m, swing kapılar önde açılıyor.
- **Mekan:** Mutfak girişi — yuvarlak lombozlu ahşap swing kapılar, paslanmaz tezgahlar, asılı bakır tencereler, gaz ocak, sabah ışığı.

### SAHNE 2 — Önlüğü Bağlıyor
- **Aksiyon:** Tezgah önünde, iki el arkada, önlük kemerini düğümlüyor. Sırttaki çapraz askılar görünür.
- **Kamera:** 2 m arkada, 1.6 m, belin arka detayına odak.
- **Mekan:** Mutfak prep alanı — paslanmaz tezgah, yukarıda bakır tencereler, mıknatıs şeritte bıçaklar, kesme tahtaları.

### SAHNE 3 — Izgara Ateşi
- **Aksiyon:** Endüstriyel ızgaranın önünde hafif çömelmiş, sağ el gaz vanası, mavi-turuncu alev tutuşuyor.
- **Kamera:** 2 m arkada, 1.5 m, omuz üstü hafif alt açı.
- **Mekan:** Izgara istasyonu — paslanmaz endüstriyel gaz ızgara, döküm demir ızgara teli, davlumbaz, arkada tuğla duvar.

### SAHNE 4 — Tezgahta Sebze Doğruyor
- **Aksiyon:** Ahşap kesme tahtasında, sağ elde şef bıçağı hareket halinde, sebze doğruyor.
- **Kamera:** 2 m arkada, 1.6 m, omuz üstü hafif aşağı.
- **Mekan:** Prep istasyonu — büyük ahşap kesme tahtası, taze domates/soğan/biber/bitki, paslanmaz tezgah.

### SAHNE 5 — Salonu Kontrol Ediyor
- **Aksiyon:** Restore edilmiş salon — masalar arasında yavaş yürüyor, eli sandalye arkalığına dokunuyor.
- **Kamera:** 3 m arkada, 1.7 m, perspektifte tablolar.
- **Mekan:** Restore NORTH salonu — beyaz örtülü ahşap masalar, vintage endüstriyel pendant ışıklar, tuğla duvarlar, pencereden altın sabah ışığı.

### SAHNE 6 — Pencerede Bekleyiş (cutscene)
- **Aksiyon:** Büyük pencere önünde durur, dışarı bakar, eller önlük cebinde.
- **Kamera:** CUTSCENE — 2 m arkada, 1.6 m, sağ tarafta pencere ve sokak.
- **Mekan:** Pencerden cam üzerinden ters NORTH yazısı, sokakta altın sabah ışığı, arkada boş hazır salon, havada toz parçacıkları.
