# WhisprPro Roadmap

## Current State (v1.0)

- [x] Trascrizione file audio/video (mp3, wav, m4a, mp4, mov, aac, flac, ogg)
- [x] Registrazione live da microfono
- [x] Tutti i modelli Whisper (tiny → large-v3-turbo)
- [x] Supporto multilingua (100+ lingue + auto-detect)
- [x] Editor integrato con sync audio
- [x] Speaker diarization automatica (Core ML)
- [x] Export SRT, VTT, TXT, JSON, PDF
- [x] Ricerca nel transcript con highlight
- [x] Rimozione automatica filler words
- [x] Drag & drop file
- [x] Download e gestione modelli in-app
- [x] Player audio con velocità variabile
- [x] Merge/split segmenti
- [x] Rinomina speaker inline
- [x] Trascrizione 100% locale, nessun dato esce dal Mac
- [x] Metal/GPU acceleration (via whisper.cpp)
- [x] Progresso download modelli in tempo reale

---

## v1.1 — Quick Wins

Piccole feature ad alto impatto, implementabili rapidamente.

### Trascrizione

- [ ] **Batch transcribe** — trascrivere più file in sequenza, con coda visibile e progresso per ciascuno
- [ ] **Traduzione via Whisper** — flag `--translate` per tradurre qualsiasi lingua in inglese durante la trascrizione
- [ ] **Ignora segmenti [SILENCE]** — filtrare automaticamente i segmenti vuoti o con solo silenzio/rumore
- [ ] **Custom GGML models** — importare modelli .bin personalizzati tramite file picker
- [ ] **Custom starting timestamp** — impostare un offset temporale iniziale per il transcript

### Audio/Video

- [ ] **System audio recording** — registrare audio di sistema per catturare meeting Zoom, Teams, etc. (via ScreenCaptureKit)
- [ ] **Playback speed fino a 3x** — estendere il range di velocità da 0.5x–2x a 0.5x–3x
- [ ] **Inline video player** — player video integrato con subtitles sincronizzati per file MP4/MOV

### UI/UX

- [ ] **Compact mode** — toggle per nascondere timestamps e mostrare solo il testo
- [ ] **Star/favorite segmenti** — segnare segmenti importanti per trovarli velocemente
- [ ] **Copia transcript/sezioni** — pulsante per copiare tutto o la selezione negli appunti

### Export

- [ ] **Export DOCX** — esportazione in formato Word
- [ ] **Export Markdown** — esportazione .md
- [ ] **Export HTML** — esportazione con styling
- [ ] **Export CSV** — esportazione tabellare (timestamp, speaker, testo)
- [ ] **Custom export formats** — template personalizzabili per stili di esportazione preferiti

---

## v1.2 — Integrazioni AI

Connessione a modelli LLM per post-processing intelligente.

### Provider supportati

- [ ] **OpenAI (ChatGPT)** — GPT-4o, GPT-4o-mini (con propria API key)
- [ ] **Anthropic (Claude)** — Claude 4 Sonnet/Opus (con propria API key)
- [ ] **Ollama** — modelli locali (Llama, Mistral, etc.)
- [ ] **Groq** — inferenza veloce
- [ ] **DeepSeek** — modelli open
- [ ] **xAI (Grok)** — integrazione API
- [ ] **OpenRouter** — accesso unificato a tutti i provider
- [ ] **Custom OpenAI-compatible endpoints** — qualsiasi API compatibile OpenAI
- [ ] **Azure AI** — modelli Microsoft Azure

### Funzionalità AI

- [ ] **Spelling, punteggiatura e grammatica** — miglioramento automatico del testo trascritto
- [ ] **Summarization** — riassunto automatico della trascrizione
- [ ] **Prompting libero** — chiedere qualsiasi cosa sulla trascrizione (Q&A, estrazione info, etc.)
- [ ] **Traduzione completa** — tradurre l'intero transcript in qualsiasi lingua

### Traduzione

- [ ] **DeepL integration** — traduzione transcript con API key gratuita DeepL
- [ ] **Traduzione subtitles** — tradurre sottotitoli in lingue diverse
- [ ] **Subtitles multilingua** — visualizzare più lingue contemporaneamente nel player

---

## v1.3 — Pro Features

Feature avanzate per utenti power user e professionisti.

### Trascrizione avanzata

- [ ] **Realtime captions / subtitles** — sottotitoli live con traduzione in tempo reale, da microfono o audio di sistema
- [ ] **YouTube video transcription** — incollare un URL YouTube e ottenere la trascrizione
- [ ] **Watch Folder** — monitorare una cartella e trascrivere automaticamente ogni file aggiunto
- [ ] **Podcast multi-track** — combinare tracce audio separate per ciascun host

### Modelli alternativi

- [ ] **WhisperKit support** — modelli ottimizzati Apple Silicon via Core ML
- [ ] **Distilled models** — modelli più piccoli e veloci con qualità comparabile
- [ ] **Parakeet v2** — fino a 300x realtime su Mac M-series

### Cloud Transcription

- [ ] **OpenAI Whisper API** — trascrizione via cloud
- [ ] **ElevenLabs Scribe** — trascrizione cloud ElevenLabs
- [ ] **Deepgram Nova** — trascrizione cloud Deepgram
- [ ] **Groq Whisper** — trascrizione veloce via Groq
- [ ] **Custom Whisper servers** — endpoint personalizzati

### Speaker Recognition

- [ ] **Speaker recognition automatica** — identificazione speaker con modelli locali (M-series)
- [ ] **ElevenLabs speaker ID** — riconoscimento via cloud ElevenLabs
- [ ] **Deepgram speaker ID** — riconoscimento via cloud Deepgram
- [ ] **Aggiunta manuale speaker** — assegnare speaker a segmenti per export più pulito

### macOS Integration

- [ ] **Menubar app** — accesso rapido da barra menu per trascrizione ovunque
- [ ] **Spotlight-style global access** — richiamare WhisprPro da qualsiasi punto del Mac con hotkey
- [ ] **Auto-record meetings** — rilevamento automatico di Zoom, Teams, Webex, Skype, Discord e avvio registrazione

### Automazioni

- [ ] **Notion integration** — inviare transcript a Notion automaticamente
- [ ] **Obsidian integration** — salvare in vault Obsidian
- [ ] **Zapier / Make.com / n8n** — webhook per automazioni
- [ ] **Custom webhooks** — endpoint HTTP personalizzati per forwarding transcript

---

## v2.0 — Platform

Vision a lungo termine.

- [ ] **Localizzazione UI** — Inglese, Italiano, Tedesco, Francese, Spagnolo
- [ ] **Distribuzione** — DMG / Mac App Store
- [ ] **Auto-update** — aggiornamenti automatici via Sparkle
- [ ] **Keyboard shortcuts** — scorciatoie globali per tutte le azioni
- [ ] **Temi** — light/dark mode + temi custom
- [ ] **Plugin system** — architettura estensibile per feature di terze parti
- [ ] **API locale** — endpoint HTTP/WebSocket per integrazioni programmatiche
- [ ] **Formato .whispr** — file proprietario che include audio originale + trascrizione + edit per sharing

---

## Principi

1. **Privacy first** — tutto locale di default, cloud solo opt-in con API key dell'utente
2. **Performance** — Metal/GPU, modelli ottimizzati, nessun compromesso sulla velocità
3. **Open source** — codice aperto, community-driven, contribuzioni benvenute
4. **Semplicità** — interfaccia pulita, pochi click per trascrivere
5. **Estensibilità** — integrazioni e automazioni per workflow professionali
