export interface TipCard {
  id: string;
  icon?: string;
  title: string;
  body: string;
  source?: 'user' | 'suggestion';
}

export interface ShoppingItem {
  id: string;
  text: string;
  category: string;
  checked?: boolean;
  source?: 'user' | 'suggestion';
}

export interface FoodSpot {
  id: string;
  name: string;
  area?: string;
  category?: string;
  note?: string;
  mapsUrl?: string;
  source?: 'user' | 'suggestion';
}

export interface CompassBlock {
  id: string;
  title: string;
  kind: 'emergency' | 'phrases' | 'money' | 'transport' | 'hotel' | 'custom';
  content: string;
  source?: 'user' | 'suggestion';
}

export interface TripGuide {
  practicalTips: TipCard[];
  shopping: ShoppingItem[];
  foodSpots: FoodSpot[];
  compass: CompassBlock[];
  /** Kullanıcı önerileri kapattı mı */
  useSuggestions?: boolean;
}
