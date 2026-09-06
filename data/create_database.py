import sqlite3

def create_sample_database():
    """Создает тестовую базу данных с данными о городах России"""
    
    conn = sqlite3.connect('data/sample_data.db')
    cursor = conn.cursor()
    
    # Создаем таблицу городов
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS cities (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            region TEXT NOT NULL,
            population INTEGER,
            foundation_year INTEGER,
            area REAL,
            is_capital BOOLEAN DEFAULT 0
        )
    ''')
    
    # Данные о городах
    cities_data = [
        ('Москва', 'Центральный', 12635500, 1147, 2561.5, 1),
        ('Санкт-Петербург', 'Северо-Западный', 5398064, 1703, 1439.0, 0),
        ('Новосибирск', 'Сибирский', 1620162, 1893, 505.6, 0),
        ('Екатеринбург', 'Уральский', 1493749, 1723, 495.8, 0),
        ('Казань', 'Приволжский', 1257341, 1005, 425.3, 0),
        ('Нижний Новгород', 'Приволжский', 1244254, 1221, 466.5, 0),
    ]
    
    # Заполняем города
    cursor.executemany('''
        INSERT OR REPLACE INTO cities 
        (name, region, population, foundation_year, area, is_capital)
        VALUES (?, ?, ?, ?, ?, ?)
    ''', cities_data)
    
    conn.commit()
    conn.close()
    print("✅ База данных создана успешно!")
    print(f"   Добавлено городов: {len(cities_data)}")

if __name__ == "__main__":
    create_sample_database()