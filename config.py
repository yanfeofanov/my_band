import os

class Config:
    # Пути
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))
    DATA_DIR = os.path.join(BASE_DIR, 'data')
    DB_PATH = os.path.join(DATA_DIR, 'sample_data.db')
    
    # Модели
    EMBEDDING_MODEL = 'all-MiniLM-L6-v2'  # Для поиска
    GENERATION_MODEL = 'google/flan-t5-small'  # Для генерации
    
    # Параметры поиска
    TOP_K = 5
    SIMILARITY_THRESHOLD = 0.3
    
    # Параметры генерации
    MAX_LENGTH = 200
    TEMPERATURE = 0.7

config = Config()