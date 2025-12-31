import 'package:flutter/material.dart';

class InfoTab extends StatelessWidget {
  const InfoTab({super.key});

  @override
  Widget build(BuildContext context) {
    final items = _mockContacts();

    return Scaffold(
      appBar: AppBar(title: const Text('Info')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(
            'Waar kun je je vragen kwijt?',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            'Kies het onderwerp en je ziet direct bij wie je moet zijn.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          ...items.map((i) => _ContactCard(item: i)),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final _ContactTopic item;
  const _ContactCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.support_agent),
        title: Text(item.topic, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('${item.people}\n${item.email}', style: Theme.of(context).textTheme.bodyMedium),
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.mail_outline),
        onTap: () {
          // Later: mailto: openen op iOS/Android (url_launcher).
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Later koppelen we dit aan een mail-knop: ${item.email}')),
          );
        },
      ),
    );
  }
}

/* ------------------ Dummy data ------------------ */

class _ContactTopic {
  final String topic;
  final String people;
  final String email;
  const _ContactTopic({required this.topic, required this.people, required this.email});
}

List<_ContactTopic> _mockContacts() => const [
  _ContactTopic(
    topic: '(Wedstrijd)kleding',
    people: 'Claudia en Brenda',
    email: 'kleding@vvminerva.nl',
  ),
  _ContactTopic(
    topic: 'Trainingen / wedstrijden jeugd',
    people: 'Thijs en Manon',
    email: 'tc@vvminerva.nl',
  ),
];