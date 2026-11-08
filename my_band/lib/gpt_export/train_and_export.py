import torch
import json
import os
from model import CharTokenizer, MiniGPT, TextDataset, train

if __name__ == "__main__":
    device = "cuda" if torch.cuda.is_available() else "cpu"

    if not os.path.exists("input.txt"):
        print("Ошибка: создайте файл input.txt с текстом для обучения!")
        exit()

    with open("input.txt", "r", encoding="utf-8") as f:
        text = f.read()

    tokenizer = CharTokenizer(text)
    
    # 1. Сохраняем словарь (связь букв и цифр) для Flutter
    vocab_data = {
        "stoi": tokenizer.stoi,
        "itos": {str(k): v for k, v in tokenizer.itos.items()}
    }
    with open("vocab.json", "w", encoding="utf-8") as f:
        json.dump(vocab_data, f, ensure_ascii=False)

    data = torch.tensor(tokenizer.encode(text), dtype=torch.long)
    
    # Уменьшили размер блока до 32, чтобы даже на небольшом тексте обучение прошло успешно
    block_size = 32 
    
    n = int(0.9 * len(data))
    train_data = data[:n]
    val_data = data[n:]
    
    # ЗАЩИТА ОТ ОШИБКИ: Если текста мало, валидация берет те же данные, что и обучение
    if len(val_data) <= block_size:
        print("ВНИМАНИЕ: Текста маловато! Используем данные обучения для валидации.")
        val_data = train_data

    train_ds = TextDataset(train_data, block_size)
    val_ds = TextDataset(val_data, block_size)

    # ВАЖНО: block_size в модели тоже должен быть 32, чтобы совпадало с датасетом
    model = MiniGPT(vocab_size=tokenizer.vocab_size, block_size=block_size)
    
    print(f"Начинаю обучение (размер словаря: {tokenizer.vocab_size}, длина текста: {len(data)} символов)...")
    
    # Увеличили эпохи до 50, чтобы модель успела выучить текст
    model = train(model, train_ds, val_ds, epochs=50, batch_size=32, lr=3e-4, device=device)
    model.eval()

    # 2. Конвертация в ONNX для Flutter
    print("Экспорт в ONNX...")
    dummy_input = torch.randint(0, tokenizer.vocab_size, (1, block_size), dtype=torch.long)
    
    torch.onnx.export(
        model,
        dummy_input,
        "minigpt.onnx",
        export_params=True,
        opset_version=14,
        do_constant_folding=True,
        input_names=['input_ids'],
        output_names=['logits'],
        dynamic_axes={
            'input_ids': {0: 'batch_size', 1: 'sequence_length'},
            'logits': {0: 'batch_size', 1: 'sequence_length'}
        }
    )
    print("Готово! Созданы файлы vocab.json и minigpt.onnx. Переносите их во Flutter.")