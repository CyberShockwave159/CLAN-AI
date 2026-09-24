Good question — here's exactly what A-PROX sends, plus the plan to handle it in CLAN-AI2 (note: your app is at /home/jstanton/CLAN-AI2, not CLAN-AI).
What A-PROX actually sends
The image arrives as one extra SSE event in the middle of the normal stream, then the caption text continues normally:
data: {"choices":[{"delta":{"image_url":{"url":"http://127.0.0.1:8000/images/gen_1790166791469_0.png"}}}]}
- Value is the OpenAI object form delta.image_url.url (not a bare string).
- The URL is a plain HTTP GET, NO auth → returns a PNG (image/png, RGBA, ~2 MP, e.g. 1728×1152) served by GET /images/{name}.
- The event fires once, before the caption text deltas; delta.content stays a string (never an array).
- Non-streaming responses carry image_url: {"url": ...} on the outer response JSON instead.
- Default URLs use http://127.0.0.1:8000; for CLAN on another device, A-PROX's public_base_url routes them to your public host.
What CLAN-AI2 must add (capability)
The full path is parse → forward → accumulate → persist → render. The exploration confirmed none of it exists yet (no Image.network anywhere; AttachmentImage only renders local files/bytes).
Step	File	Change
1. Parse	sse_client.dart:362 + _processDataBlock	Read delta['image_url']?['url'], add imageUrl: String? to StreamChunk (43–57)
2. Forward	sse_client.dart:196–302 (filterReasoning)	Forward chunk.imageUrl through every reconstructed StreamChunk — it's silently dropped today
3. Non-stream	llama_api_service.dart	Also parse outer image_url for non-streaming responses
4. Accumulate	stream_mutation_mixin.dart:61–136	Grab imageUrl once (image arrives before text → one-shot), set on the message
5. Persist	chat_message.dart + local_storage.dart	Reuse the existing image_path field/column (v13 already has it) → zero schema migration, auto round-trip, auto cleanup hooks all work
6. Render	message_bubble.dart:437	New !isUser && imagePath != null block, mirroring the user-image block at 440–477; reuse tap-to-fullscreen (302–336)
Key decision at step 5/6 — two options:
- A (recommended): download-into-store. On receiving imageUrl, fetch the PNG and save via existing MessageAttachmentStore.saveImage, store the local ref in ChatMessage.imagePath. Zero new render code (existing AttachmentImage shows it), persists offline, survives server restarts.
- B (lighter): network image. Add Image.network(url, errorBuilder:) to the bubble and store the URL string. One new widget, but re-fetches on every render and breaks if the URL becomes unreachable.
I'd go with A since it reuses CLAN's existing attachment plumbing intact.
Want me to implement option A (or B) in CLAN-AI2?
