class EmojiHelper {
  static const Map<String, String> _keywordToEmoji = {
    // Comida
    "comer": "🍽️",
    "comida": "🍽️",
    "jantar": "🍽️",
    "almoço": "🍽️",
    "snack": "🍽️",

    "pizza": "🍕",
    "hamburguer": "🍔",
    "burger": "🍔",
    "lanche": "🍔",
    "pão": "🍔",

    "sushi": "🍣",
    "japonesa": "🍣",
    "temaki": "🍣",

    "açai": "🥤",
    "acai": "🥤",

    "churrasco": "🥩",
    "bbq": "🥩",

    "pastel": "🥟",
    "coxinha": "🥟",
    "padaria": "🥐",

    "mexicana": "🌮",
    "taco": "🌮",

    "massa": "🍝",
    "macarrão": "🍝",

    // Bebidas
    "bar": "🍺",
    "happy hour": "🍺",
    "chopp": "🍺",
    "cerveja": "🍺",

    "drink": "🍹",
    "drinks": "🍹",
    "coquetel": "🍹",

    "vinho": "🍷",
    "vinhos": "🍷",

    "boteco": "🍻",
    "pub": "🍺",

    // Música/Eventos
    "show": "🎤",
    "shows": "🎤",
    "ao vivo": "🎤",

    "pagode": "🥁",
    "samba": "🥁",

    "sertanejo": "🤠",
    "modão": "🤠",
    "universitário": "🤠",

    "funk": "🎧",
    "eletrônica": "🎧",
    "rave": "🎧",
    "techno": "🎧",
    "dj": "🎧",

    "festival": "🎪",
    "evento": "🎪",
    "festão": "🎪",

    "balada": "🕺",
    "night": "🕺",
    "festa": "🕺",

    // Chill/Cultura
    "café": "☕",
    "cafezinho": "☕",
    "starbucks": "☕",

    "chá": "🫖",

    "livro": "📚",
    "ler": "📚",
    "estudar": "📚",

    "fotografia": "📸",
    "foto": "📸",

    "parque": "🌳",
    "praça": "🌿",
    "piquenique": "🧺",

    "museu": "🖼️",
    "arte": "🎨",
    "exposição": "🎨",

    // Esportes/Ar livre
    "correr": "🏃",
    "corrida": "🏃",
    "run": "🏃",

    "caminhar": "🚶",
    "andar": "🚶",

    "pedalar": "🚴",
    "bike": "🚴",

    "academia": "🏋️",
    "treinar": "🏋️",
    "gym": "🏋️",

    "yoga": "🧘",
    "pilates": "🧘",

    "praia": "🏖️",
    "mar": "🌊",
    "sol": "☀️",

    "pôr do sol": "🌅",

    // Entretenimento
    "videogame": "🎮",
    "jogar": "🎮",
    "games": "🎮",

    "netflix": "📺",
    "filme": "🎬",
    "cinema": "🎬",
    "série": "📺",

    "boardgame": "🎲",
    "tabuleiro": "🎲",
    "uno": "🎴",

    "cozinhar": "🍳",
    "culinária": "🍳",

    "violão": "🎸",
    "instrumento": "🎸",

    // Outros
    "boliche": "🎳",
    "sinuca": "🎱",
    "bilhar": "🎱",

    "shopping": "🛍️",
    "compras": "🛍️",

    "passear": "🚶",
    "dar uma volta": "🚗",
    "rolê": "🌟",

    "rooftop": "🏙️",
  };

  /// Retorna um emoji baseado no texto digitado.
  /// Verifica se alguma palavra-chave está contida no texto.
  static String? getEmojiForText(String text) {
    final lowerText = text.toLowerCase();
    
    // Itera sobre o mapa para encontrar uma correspondência
    for (final entry in _keywordToEmoji.entries) {
      // Verifica se a palavra chave está presente no texto como uma palavra completa ou parte dela?
      // O requisito diz "palavra chave no text field".
      // Vamos usar contains para ser mais abrangente, mas idealmente seria word boundary.
      // Dado o exemplo "pizza" -> 🍕, se eu digitar "eu quero pizza", deve funcionar.
      if (lowerText.contains(entry.key)) {
        return entry.value;
      }
    }
    
    return null;
  }
}
