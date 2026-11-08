import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
import math


class CharTokenizer:
    def __init__(self, text):
        self.chars = sorted(list(set(text)))
        self.stoi = {c: i for i, c in enumerate(self.chars)}
        self.itos = {i: c for c, i in self.stoi.items()}
        self.vocab_size = len(self.chars)

    def encode(self, s):
        return [self.stoi[c] for c in s if c in self.stoi]

    def decode(self, ids):
        return ''.join(self.itos[i] for i in ids)


class TextDataset(Dataset):
    def __init__(self, data, block_size):
        self.data = data
        self.block_size = block_size

    def __len__(self):
        return len(self.data) - self.block_size

    def __getitem__(self, idx):
        chunk = self.data[idx: idx + self.block_size + 1]
        x = torch.tensor(chunk[:-1], dtype=torch.long)
        y = torch.tensor(chunk[1:], dtype=torch.long)
        return x, y


class CausalSelfAttention(nn.Module):
    def __init__(self, n_embd, n_head, block_size, dropout=0.1):
        super().__init__()
        assert n_embd % n_head == 0
        self.n_head = n_head
        self.head_dim = n_embd // n_head
        self.qkv = nn.Linear(n_embd, 3 * n_embd)
        self.proj = nn.Linear(n_embd, n_embd)
        self.dropout = nn.Dropout(dropout)
        self.register_buffer(
            "mask",
            torch.tril(torch.ones(block_size, block_size)).view(1, 1, block_size, block_size),
        )

    def forward(self, x):
        B, T, C = x.shape
        qkv = self.qkv(x)
        q, k, v = qkv.split(C, dim=2)

        q = q.view(B, T, self.n_head, self.head_dim).transpose(1, 2)
        k = k.view(B, T, self.n_head, self.head_dim).transpose(1, 2)
        v = v.view(B, T, self.n_head, self.head_dim).transpose(1, 2)

        att = (q @ k.transpose(-2, -1)) / math.sqrt(self.head_dim)
        att = att.masked_fill(self.mask[:, :, :T, :T] == 0, float('-inf'))
        att = F.softmax(att, dim=-1)
        att = self.dropout(att)

        out = att @ v
        out = out.transpose(1, 2).contiguous().view(B, T, C)
        return self.proj(out)


class MLP(nn.Module):
    """Feed-forward блок трансформера: расширяем в 4x, GELU, сжимаем обратно."""
    def __init__(self, n_embd, dropout=0.1):
        super().__init__()
        self.fc1 = nn.Linear(n_embd, 4 * n_embd)
        self.fc2 = nn.Linear(4 * n_embd, n_embd)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x):
        return self.fc2(self.dropout(F.gelu(self.fc1(x))))


class Block(nn.Module):
    """Один слой трансформера: pre-LN + attention + residual, pre-LN + MLP + residual."""
    def __init__(self, n_embd, n_head, block_size, dropout=0.1):
        super().__init__()
        self.ln1 = nn.LayerNorm(n_embd)
        self.attn = CausalSelfAttention(n_embd, n_head, block_size, dropout)
        self.ln2 = nn.LayerNorm(n_embd)
        self.mlp = MLP(n_embd, dropout)

    def forward(self, x):
        x = x + self.attn(self.ln1(x))   # residual вокруг attention
        x = x + self.mlp(self.ln2(x))    # residual вокруг MLP
        return x


class MiniGPT(nn.Module):
    def __init__(self, vocab_size, block_size, n_embd=128, n_head=4,
                 n_layer=4, dropout=0.1):
        super().__init__()
        self.block_size = block_size

        # 1. Эмбеддинги токенов + позиций
        self.tok_emb = nn.Embedding(vocab_size, n_embd)
        self.pos_emb = nn.Embedding(block_size, n_embd)
        self.drop = nn.Dropout(dropout)

        # 2. Стек трансформер-блоков
        self.blocks = nn.ModuleList(
            [Block(n_embd, n_head, block_size, dropout) for _ in range(n_layer)]
        )

        # 3. Финальный слой нормы и голова на словарь
        self.ln_f = nn.LayerNorm(n_embd)
        self.lm_head = nn.Linear(n_embd, vocab_size)

        self.apply(self._init_weights)

    def _init_weights(self, m):
        if isinstance(m, nn.Linear):
            nn.init.normal_(m.weight, std=0.02)
            if m.bias is not None:
                nn.init.zeros_(m.bias)
        elif isinstance(m, nn.Embedding):
            nn.init.normal_(m.weight, std=0.02)

    def forward(self, idx, targets=None):
        B, T = idx.shape
        assert T <= self.block_size, f"T={T} > block_size={self.block_size}"

        pos = torch.arange(T, device=idx.device).unsqueeze(0)  # (1, T)
        x = self.drop(self.tok_emb(idx) + self.pos_emb(pos))   # (B, T, C)

        for block in self.blocks:
            x = block(x)

        x = self.ln_f(x)
        logits = self.lm_head(x)                                # (B, T, vocab_size)

        loss = None
        if targets is not None:
            loss = F.cross_entropy(
                logits.view(-1, logits.size(-1)),
                targets.view(-1),
            )
        return logits, loss

    @torch.no_grad()
    def generate(self, idx, max_new_tokens, temperature=1.0, top_k=None):
        """Автогенерация: подаём контекст, сэмплируем следующий токен, сдвигаем окно."""
        for _ in range(max_new_tokens):
            idx_cond = idx[:, -self.block_size:]
            logits, _ = self(idx_cond)
            logits = logits[:, -1, :] / temperature          # берём последний шаг

            if top_k is not None:
                v, _ = torch.topk(logits, top_k)
                logits[logits < v[:, [-1]]] = -float('inf')

            probs = F.softmax(logits, dim=-1)
            next_id = torch.multinomial(probs, num_samples=1)
            idx = torch.cat([idx, next_id], dim=1)
        return idx


def train(model, train_ds, val_ds, epochs, batch_size, lr, device):
    model.to(device)
    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_ds, batch_size=batch_size)
    opt = torch.optim.AdamW(model.parameters(), lr=lr)

    for epoch in range(epochs):
        model.train()
        total = 0.0
        for x, y in train_loader:
            x, y = x.to(device), y.to(device)
            _, loss = model(x, y)
            opt.zero_grad()
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
            opt.step()
            total += loss.item()

        train_loss = total / len(train_loader)

        model.eval()
        vtotal = 0.0
        with torch.no_grad():
            for x, y in val_loader:
                x, y = x.to(device), y.to(device)
                _, loss = model(x, y)
                vtotal += loss.item()

        val_loss = vtotal / len(val_loader)
        print(f"epoch {epoch+1}/{epochs} | train {train_loss:.4f} | val {val_loss:.4f}")

    return model


# ---------------- Пример запуска ----------------
if __name__ == "__main__":
    device = "cuda" if torch.cuda.is_available() else "cpu"

    with open("input.txt", "r", encoding="utf-8") as f:
        text = f.read()

    tokenizer = CharTokenizer(text)
    data = torch.tensor(tokenizer.encode(text), dtype=torch.long)

    block_size = 64
    n = int(0.9 * len(data))
    train_ds = TextDataset(data[:n], block_size)
    val_ds = TextDataset(data[n:], block_size)

    model = MiniGPT(
        vocab_size=tokenizer.vocab_size,
        block_size=block_size,
        n_embd=128,
        n_head=4,
        n_layer=4,
    )

    train(model, train_ds, val_ds, epochs=5, batch_size=32, lr=3e-4, device=device)

    # генерация
    start = torch.tensor([tokenizer.encode("The ")],
                         dtype=torch.long).to(device)
    out = model.generate(start, max_new_tokens=200, temperature=0.8, top_k=40)
    print(tokenizer.decode(out[0].tolist()))