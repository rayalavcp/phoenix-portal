import 'package:flutter/foundation.dart';

/// Telugu word of the day: the word, how to say it, and what it means.
@immutable
class TeluguWord {
  const TeluguWord(this.telugu, this.say, this.meaning);
  final String telugu;
  final String say;
  final String meaning;
}

const teluguWords = <TeluguWord>[
  TeluguWord('అమ్మ', 'Amma', 'Mother'),
  TeluguWord('నాన్న', 'Nanna', 'Father'),
  TeluguWord('అవును', 'Avunu', 'Yes'),
  TeluguWord('కాదు', 'Kaadu', 'No'),
  TeluguWord('నీళ్ళు', 'Neellu', 'Water'),
  TeluguWord('అన్నం', 'Annam', 'Rice'),
  TeluguWord('పాలు', 'Paalu', 'Milk'),
  TeluguWord('ఇల్లు', 'Illu', 'House'),
  TeluguWord('బడి', 'Badi', 'School'),
  TeluguWord('పుస్తకం', 'Pustakam', 'Book'),
  TeluguWord('స్నేహితుడు', 'Snehitudu', 'Friend'),
  TeluguWord('ధన్యవాదాలు', 'Dhanyavaadaalu', 'Thank you'),
  TeluguWord('నమస్కారం', 'Namaskaaram', 'Hello'),
  TeluguWord('సూర్యుడు', 'Sooryudu', 'Sun'),
  TeluguWord('చంద్రుడు', 'Chandrudu', 'Moon'),
  TeluguWord('నక్షత్రం', 'Nakshatram', 'Star'),
  TeluguWord('వాన', 'Vaana', 'Rain'),
  TeluguWord('చెట్టు', 'Chettu', 'Tree'),
  TeluguWord('పువ్వు', 'Puvvu', 'Flower'),
  TeluguWord('పండు', 'Pandu', 'Fruit'),
  TeluguWord('మామిడి', 'Maamidi', 'Mango'),
  TeluguWord('అరటి', 'Arati', 'Banana'),
  TeluguWord('కుక్క', 'Kukka', 'Dog'),
  TeluguWord('పిల్లి', 'Pilli', 'Cat'),
  TeluguWord('ఆవు', 'Aavu', 'Cow'),
  TeluguWord('ఏనుగు', 'Enugu', 'Elephant'),
  TeluguWord('పక్షి', 'Pakshi', 'Bird'),
  TeluguWord('చేప', 'Chepa', 'Fish'),
  TeluguWord('ఎరుపు', 'Erupu', 'Red'),
  TeluguWord('నీలం', 'Neelam', 'Blue'),
  TeluguWord('పచ్చ', 'Paccha', 'Green'),
  TeluguWord('పసుపు', 'Pasupu', 'Yellow'),
  TeluguWord('తెలుపు', 'Telupu', 'White'),
  TeluguWord('నలుపు', 'Nalupu', 'Black'),
  TeluguWord('ఒకటి', 'Okati', 'One'),
  TeluguWord('రెండు', 'Rendu', 'Two'),
  TeluguWord('మూడు', 'Moodu', 'Three'),
  TeluguWord('నాలుగు', 'Naalugu', 'Four'),
  TeluguWord('ఐదు', 'Aidu', 'Five'),
  TeluguWord('పది', 'Padi', 'Ten'),
  TeluguWord('ఈరోజు', 'Eeroju', 'Today'),
  TeluguWord('రేపు', 'Repu', 'Tomorrow'),
  TeluguWord('నిన్న', 'Ninna', 'Yesterday'),
  TeluguWord('ఉదయం', 'Udayam', 'Morning'),
  TeluguWord('రాత్రి', 'Raatri', 'Night'),
  TeluguWord('సంతోషం', 'Santosham', 'Happiness'),
  TeluguWord('ప్రేమ', 'Prema', 'Love'),
  TeluguWord('పెద్ద', 'Pedda', 'Big'),
  TeluguWord('చిన్న', 'Chinna', 'Small'),
  TeluguWord('వేడి', 'Vedi', 'Hot'),
  TeluguWord('చల్లని', 'Challani', 'Cold'),
  TeluguWord('తినండి', 'Tinandi', 'Please eat'),
  TeluguWord('రండి', 'Randi', 'Please come'),
  TeluguWord('వెళ్ళు', 'Vellu', 'Go'),
  TeluguWord('ఆట', 'Aata', 'Game'),
  TeluguWord('పాట', 'Paata', 'Song'),
  TeluguWord('బొమ్మ', 'Bomma', 'Toy / picture'),
  TeluguWord('తాత', 'Taata', 'Grandfather'),
  TeluguWord('అమ్మమ్మ', 'Ammamma', 'Grandmother (mother\'s mother)'),
  TeluguWord('అక్క', 'Akka', 'Elder sister'),
  TeluguWord('చెల్లి', 'Chelli', 'Younger sister'),
  TeluguWord('అన్న', 'Anna', 'Elder brother'),
  TeluguWord('తమ్ముడు', 'Tammudu', 'Younger brother'),
];

/// The same word all day, a new one each day.
TeluguWord teluguWordOfTheDay(DateTime day) {
  final n = DateTime.utc(day.year, day.month, day.day).difference(DateTime.utc(2024)).inDays;
  return teluguWords[n % teluguWords.length];
}
