// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MembersTable extends Members with TableInfo<$MembersTable, Member> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gymIdMeta = const VerificationMeta('gymId');
  @override
  late final GeneratedColumn<String> gymId = GeneratedColumn<String>(
    'gym_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _homeLocationIdMeta = const VerificationMeta(
    'homeLocationId',
  );
  @override
  late final GeneratedColumn<String> homeLocationId = GeneratedColumn<String>(
    'home_location_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _memberCodeMeta = const VerificationMeta(
    'memberCode',
  );
  @override
  late final GeneratedColumn<String> memberCode = GeneratedColumn<String>(
    'member_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _firstNameMeta = const VerificationMeta(
    'firstName',
  );
  @override
  late final GeneratedColumn<String> firstName = GeneratedColumn<String>(
    'first_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastNameMeta = const VerificationMeta(
    'lastName',
  );
  @override
  late final GeneratedColumn<String> lastName = GeneratedColumn<String>(
    'last_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _dateOfBirthMeta = const VerificationMeta(
    'dateOfBirth',
  );
  @override
  late final GeneratedColumn<DateTime> dateOfBirth = GeneratedColumn<DateTime>(
    'date_of_birth',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _memberTypeMeta = const VerificationMeta(
    'memberType',
  );
  @override
  late final GeneratedColumn<String> memberType = GeneratedColumn<String>(
    'member_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _currentEndDateMeta = const VerificationMeta(
    'currentEndDate',
  );
  @override
  late final GeneratedColumn<DateTime> currentEndDate =
      GeneratedColumn<DateTime>(
        'current_end_date',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _currentPlanCategoryMeta =
      const VerificationMeta('currentPlanCategory');
  @override
  late final GeneratedColumn<String> currentPlanCategory =
      GeneratedColumn<String>(
        'current_plan_category',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDirtyMeta = const VerificationMeta(
    'isDirty',
  );
  @override
  late final GeneratedColumn<bool> isDirty = GeneratedColumn<bool>(
    'is_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    gymId,
    homeLocationId,
    memberCode,
    firstName,
    lastName,
    phone,
    email,
    dateOfBirth,
    memberType,
    notes,
    currentEndDate,
    currentPlanCategory,
    createdAt,
    updatedAt,
    archivedAt,
    isDirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'members';
  @override
  VerificationContext validateIntegrity(
    Insertable<Member> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('gym_id')) {
      context.handle(
        _gymIdMeta,
        gymId.isAcceptableOrUnknown(data['gym_id']!, _gymIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gymIdMeta);
    }
    if (data.containsKey('home_location_id')) {
      context.handle(
        _homeLocationIdMeta,
        homeLocationId.isAcceptableOrUnknown(
          data['home_location_id']!,
          _homeLocationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_homeLocationIdMeta);
    }
    if (data.containsKey('member_code')) {
      context.handle(
        _memberCodeMeta,
        memberCode.isAcceptableOrUnknown(data['member_code']!, _memberCodeMeta),
      );
    }
    if (data.containsKey('first_name')) {
      context.handle(
        _firstNameMeta,
        firstName.isAcceptableOrUnknown(data['first_name']!, _firstNameMeta),
      );
    } else if (isInserting) {
      context.missing(_firstNameMeta);
    }
    if (data.containsKey('last_name')) {
      context.handle(
        _lastNameMeta,
        lastName.isAcceptableOrUnknown(data['last_name']!, _lastNameMeta),
      );
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    }
    if (data.containsKey('date_of_birth')) {
      context.handle(
        _dateOfBirthMeta,
        dateOfBirth.isAcceptableOrUnknown(
          data['date_of_birth']!,
          _dateOfBirthMeta,
        ),
      );
    }
    if (data.containsKey('member_type')) {
      context.handle(
        _memberTypeMeta,
        memberType.isAcceptableOrUnknown(data['member_type']!, _memberTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_memberTypeMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('current_end_date')) {
      context.handle(
        _currentEndDateMeta,
        currentEndDate.isAcceptableOrUnknown(
          data['current_end_date']!,
          _currentEndDateMeta,
        ),
      );
    }
    if (data.containsKey('current_plan_category')) {
      context.handle(
        _currentPlanCategoryMeta,
        currentPlanCategory.isAcceptableOrUnknown(
          data['current_plan_category']!,
          _currentPlanCategoryMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('is_dirty')) {
      context.handle(
        _isDirtyMeta,
        isDirty.isAcceptableOrUnknown(data['is_dirty']!, _isDirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Member map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Member(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      gymId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gym_id'],
      )!,
      homeLocationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}home_location_id'],
      )!,
      memberCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_code'],
      )!,
      firstName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}first_name'],
      )!,
      lastName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_name'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      dateOfBirth: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date_of_birth'],
      ),
      memberType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_type'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      currentEndDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}current_end_date'],
      ),
      currentPlanCategory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_plan_category'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      isDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dirty'],
      )!,
    );
  }

  @override
  $MembersTable createAlias(String alias) {
    return $MembersTable(attachedDatabase, alias);
  }
}

class Member extends DataClass implements Insertable<Member> {
  final String id;
  final String gymId;
  final String homeLocationId;
  final String memberCode;
  final String firstName;
  final String lastName;
  final String phone;
  final String email;
  final DateTime? dateOfBirth;
  final String memberType;
  final String notes;
  final DateTime? currentEndDate;
  final String? currentPlanCategory;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? archivedAt;
  final bool isDirty;
  const Member({
    required this.id,
    required this.gymId,
    required this.homeLocationId,
    required this.memberCode,
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.email,
    this.dateOfBirth,
    required this.memberType,
    required this.notes,
    this.currentEndDate,
    this.currentPlanCategory,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
    required this.isDirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['gym_id'] = Variable<String>(gymId);
    map['home_location_id'] = Variable<String>(homeLocationId);
    map['member_code'] = Variable<String>(memberCode);
    map['first_name'] = Variable<String>(firstName);
    map['last_name'] = Variable<String>(lastName);
    map['phone'] = Variable<String>(phone);
    map['email'] = Variable<String>(email);
    if (!nullToAbsent || dateOfBirth != null) {
      map['date_of_birth'] = Variable<DateTime>(dateOfBirth);
    }
    map['member_type'] = Variable<String>(memberType);
    map['notes'] = Variable<String>(notes);
    if (!nullToAbsent || currentEndDate != null) {
      map['current_end_date'] = Variable<DateTime>(currentEndDate);
    }
    if (!nullToAbsent || currentPlanCategory != null) {
      map['current_plan_category'] = Variable<String>(currentPlanCategory);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    map['is_dirty'] = Variable<bool>(isDirty);
    return map;
  }

  MembersCompanion toCompanion(bool nullToAbsent) {
    return MembersCompanion(
      id: Value(id),
      gymId: Value(gymId),
      homeLocationId: Value(homeLocationId),
      memberCode: Value(memberCode),
      firstName: Value(firstName),
      lastName: Value(lastName),
      phone: Value(phone),
      email: Value(email),
      dateOfBirth: dateOfBirth == null && nullToAbsent
          ? const Value.absent()
          : Value(dateOfBirth),
      memberType: Value(memberType),
      notes: Value(notes),
      currentEndDate: currentEndDate == null && nullToAbsent
          ? const Value.absent()
          : Value(currentEndDate),
      currentPlanCategory: currentPlanCategory == null && nullToAbsent
          ? const Value.absent()
          : Value(currentPlanCategory),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      isDirty: Value(isDirty),
    );
  }

  factory Member.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Member(
      id: serializer.fromJson<String>(json['id']),
      gymId: serializer.fromJson<String>(json['gymId']),
      homeLocationId: serializer.fromJson<String>(json['homeLocationId']),
      memberCode: serializer.fromJson<String>(json['memberCode']),
      firstName: serializer.fromJson<String>(json['firstName']),
      lastName: serializer.fromJson<String>(json['lastName']),
      phone: serializer.fromJson<String>(json['phone']),
      email: serializer.fromJson<String>(json['email']),
      dateOfBirth: serializer.fromJson<DateTime?>(json['dateOfBirth']),
      memberType: serializer.fromJson<String>(json['memberType']),
      notes: serializer.fromJson<String>(json['notes']),
      currentEndDate: serializer.fromJson<DateTime?>(json['currentEndDate']),
      currentPlanCategory: serializer.fromJson<String?>(
        json['currentPlanCategory'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      isDirty: serializer.fromJson<bool>(json['isDirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'gymId': serializer.toJson<String>(gymId),
      'homeLocationId': serializer.toJson<String>(homeLocationId),
      'memberCode': serializer.toJson<String>(memberCode),
      'firstName': serializer.toJson<String>(firstName),
      'lastName': serializer.toJson<String>(lastName),
      'phone': serializer.toJson<String>(phone),
      'email': serializer.toJson<String>(email),
      'dateOfBirth': serializer.toJson<DateTime?>(dateOfBirth),
      'memberType': serializer.toJson<String>(memberType),
      'notes': serializer.toJson<String>(notes),
      'currentEndDate': serializer.toJson<DateTime?>(currentEndDate),
      'currentPlanCategory': serializer.toJson<String?>(currentPlanCategory),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'isDirty': serializer.toJson<bool>(isDirty),
    };
  }

  Member copyWith({
    String? id,
    String? gymId,
    String? homeLocationId,
    String? memberCode,
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    Value<DateTime?> dateOfBirth = const Value.absent(),
    String? memberType,
    String? notes,
    Value<DateTime?> currentEndDate = const Value.absent(),
    Value<String?> currentPlanCategory = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> archivedAt = const Value.absent(),
    bool? isDirty,
  }) => Member(
    id: id ?? this.id,
    gymId: gymId ?? this.gymId,
    homeLocationId: homeLocationId ?? this.homeLocationId,
    memberCode: memberCode ?? this.memberCode,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    dateOfBirth: dateOfBirth.present ? dateOfBirth.value : this.dateOfBirth,
    memberType: memberType ?? this.memberType,
    notes: notes ?? this.notes,
    currentEndDate: currentEndDate.present
        ? currentEndDate.value
        : this.currentEndDate,
    currentPlanCategory: currentPlanCategory.present
        ? currentPlanCategory.value
        : this.currentPlanCategory,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    isDirty: isDirty ?? this.isDirty,
  );
  Member copyWithCompanion(MembersCompanion data) {
    return Member(
      id: data.id.present ? data.id.value : this.id,
      gymId: data.gymId.present ? data.gymId.value : this.gymId,
      homeLocationId: data.homeLocationId.present
          ? data.homeLocationId.value
          : this.homeLocationId,
      memberCode: data.memberCode.present
          ? data.memberCode.value
          : this.memberCode,
      firstName: data.firstName.present ? data.firstName.value : this.firstName,
      lastName: data.lastName.present ? data.lastName.value : this.lastName,
      phone: data.phone.present ? data.phone.value : this.phone,
      email: data.email.present ? data.email.value : this.email,
      dateOfBirth: data.dateOfBirth.present
          ? data.dateOfBirth.value
          : this.dateOfBirth,
      memberType: data.memberType.present
          ? data.memberType.value
          : this.memberType,
      notes: data.notes.present ? data.notes.value : this.notes,
      currentEndDate: data.currentEndDate.present
          ? data.currentEndDate.value
          : this.currentEndDate,
      currentPlanCategory: data.currentPlanCategory.present
          ? data.currentPlanCategory.value
          : this.currentPlanCategory,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      isDirty: data.isDirty.present ? data.isDirty.value : this.isDirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Member(')
          ..write('id: $id, ')
          ..write('gymId: $gymId, ')
          ..write('homeLocationId: $homeLocationId, ')
          ..write('memberCode: $memberCode, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('phone: $phone, ')
          ..write('email: $email, ')
          ..write('dateOfBirth: $dateOfBirth, ')
          ..write('memberType: $memberType, ')
          ..write('notes: $notes, ')
          ..write('currentEndDate: $currentEndDate, ')
          ..write('currentPlanCategory: $currentPlanCategory, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('isDirty: $isDirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    gymId,
    homeLocationId,
    memberCode,
    firstName,
    lastName,
    phone,
    email,
    dateOfBirth,
    memberType,
    notes,
    currentEndDate,
    currentPlanCategory,
    createdAt,
    updatedAt,
    archivedAt,
    isDirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Member &&
          other.id == this.id &&
          other.gymId == this.gymId &&
          other.homeLocationId == this.homeLocationId &&
          other.memberCode == this.memberCode &&
          other.firstName == this.firstName &&
          other.lastName == this.lastName &&
          other.phone == this.phone &&
          other.email == this.email &&
          other.dateOfBirth == this.dateOfBirth &&
          other.memberType == this.memberType &&
          other.notes == this.notes &&
          other.currentEndDate == this.currentEndDate &&
          other.currentPlanCategory == this.currentPlanCategory &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.archivedAt == this.archivedAt &&
          other.isDirty == this.isDirty);
}

class MembersCompanion extends UpdateCompanion<Member> {
  final Value<String> id;
  final Value<String> gymId;
  final Value<String> homeLocationId;
  final Value<String> memberCode;
  final Value<String> firstName;
  final Value<String> lastName;
  final Value<String> phone;
  final Value<String> email;
  final Value<DateTime?> dateOfBirth;
  final Value<String> memberType;
  final Value<String> notes;
  final Value<DateTime?> currentEndDate;
  final Value<String?> currentPlanCategory;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> archivedAt;
  final Value<bool> isDirty;
  final Value<int> rowid;
  const MembersCompanion({
    this.id = const Value.absent(),
    this.gymId = const Value.absent(),
    this.homeLocationId = const Value.absent(),
    this.memberCode = const Value.absent(),
    this.firstName = const Value.absent(),
    this.lastName = const Value.absent(),
    this.phone = const Value.absent(),
    this.email = const Value.absent(),
    this.dateOfBirth = const Value.absent(),
    this.memberType = const Value.absent(),
    this.notes = const Value.absent(),
    this.currentEndDate = const Value.absent(),
    this.currentPlanCategory = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MembersCompanion.insert({
    required String id,
    required String gymId,
    required String homeLocationId,
    this.memberCode = const Value.absent(),
    required String firstName,
    this.lastName = const Value.absent(),
    this.phone = const Value.absent(),
    this.email = const Value.absent(),
    this.dateOfBirth = const Value.absent(),
    required String memberType,
    this.notes = const Value.absent(),
    this.currentEndDate = const Value.absent(),
    this.currentPlanCategory = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.archivedAt = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       gymId = Value(gymId),
       homeLocationId = Value(homeLocationId),
       firstName = Value(firstName),
       memberType = Value(memberType),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Member> custom({
    Expression<String>? id,
    Expression<String>? gymId,
    Expression<String>? homeLocationId,
    Expression<String>? memberCode,
    Expression<String>? firstName,
    Expression<String>? lastName,
    Expression<String>? phone,
    Expression<String>? email,
    Expression<DateTime>? dateOfBirth,
    Expression<String>? memberType,
    Expression<String>? notes,
    Expression<DateTime>? currentEndDate,
    Expression<String>? currentPlanCategory,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? archivedAt,
    Expression<bool>? isDirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (gymId != null) 'gym_id': gymId,
      if (homeLocationId != null) 'home_location_id': homeLocationId,
      if (memberCode != null) 'member_code': memberCode,
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (memberType != null) 'member_type': memberType,
      if (notes != null) 'notes': notes,
      if (currentEndDate != null) 'current_end_date': currentEndDate,
      if (currentPlanCategory != null)
        'current_plan_category': currentPlanCategory,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (isDirty != null) 'is_dirty': isDirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MembersCompanion copyWith({
    Value<String>? id,
    Value<String>? gymId,
    Value<String>? homeLocationId,
    Value<String>? memberCode,
    Value<String>? firstName,
    Value<String>? lastName,
    Value<String>? phone,
    Value<String>? email,
    Value<DateTime?>? dateOfBirth,
    Value<String>? memberType,
    Value<String>? notes,
    Value<DateTime?>? currentEndDate,
    Value<String?>? currentPlanCategory,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? archivedAt,
    Value<bool>? isDirty,
    Value<int>? rowid,
  }) {
    return MembersCompanion(
      id: id ?? this.id,
      gymId: gymId ?? this.gymId,
      homeLocationId: homeLocationId ?? this.homeLocationId,
      memberCode: memberCode ?? this.memberCode,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      memberType: memberType ?? this.memberType,
      notes: notes ?? this.notes,
      currentEndDate: currentEndDate ?? this.currentEndDate,
      currentPlanCategory: currentPlanCategory ?? this.currentPlanCategory,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      isDirty: isDirty ?? this.isDirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (gymId.present) {
      map['gym_id'] = Variable<String>(gymId.value);
    }
    if (homeLocationId.present) {
      map['home_location_id'] = Variable<String>(homeLocationId.value);
    }
    if (memberCode.present) {
      map['member_code'] = Variable<String>(memberCode.value);
    }
    if (firstName.present) {
      map['first_name'] = Variable<String>(firstName.value);
    }
    if (lastName.present) {
      map['last_name'] = Variable<String>(lastName.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (dateOfBirth.present) {
      map['date_of_birth'] = Variable<DateTime>(dateOfBirth.value);
    }
    if (memberType.present) {
      map['member_type'] = Variable<String>(memberType.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (currentEndDate.present) {
      map['current_end_date'] = Variable<DateTime>(currentEndDate.value);
    }
    if (currentPlanCategory.present) {
      map['current_plan_category'] = Variable<String>(
        currentPlanCategory.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (isDirty.present) {
      map['is_dirty'] = Variable<bool>(isDirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembersCompanion(')
          ..write('id: $id, ')
          ..write('gymId: $gymId, ')
          ..write('homeLocationId: $homeLocationId, ')
          ..write('memberCode: $memberCode, ')
          ..write('firstName: $firstName, ')
          ..write('lastName: $lastName, ')
          ..write('phone: $phone, ')
          ..write('email: $email, ')
          ..write('dateOfBirth: $dateOfBirth, ')
          ..write('memberType: $memberType, ')
          ..write('notes: $notes, ')
          ..write('currentEndDate: $currentEndDate, ')
          ..write('currentPlanCategory: $currentPlanCategory, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('isDirty: $isDirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MembershipPlansTable extends MembershipPlans
    with TableInfo<$MembershipPlansTable, MembershipPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembershipPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gymIdMeta = const VerificationMeta('gymId');
  @override
  late final GeneratedColumn<String> gymId = GeneratedColumn<String>(
    'gym_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _durationValueMeta = const VerificationMeta(
    'durationValue',
  );
  @override
  late final GeneratedColumn<int> durationValue = GeneratedColumn<int>(
    'duration_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationUnitMeta = const VerificationMeta(
    'durationUnit',
  );
  @override
  late final GeneratedColumn<String> durationUnit = GeneratedColumn<String>(
    'duration_unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _priceCentavosMeta = const VerificationMeta(
    'priceCentavos',
  );
  @override
  late final GeneratedColumn<int> priceCentavos = GeneratedColumn<int>(
    'price_centavos',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDayPassMeta = const VerificationMeta(
    'isDayPass',
  );
  @override
  late final GeneratedColumn<bool> isDayPass = GeneratedColumn<bool>(
    'is_day_pass',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_day_pass" IN (0, 1))',
    ),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isDirtyMeta = const VerificationMeta(
    'isDirty',
  );
  @override
  late final GeneratedColumn<bool> isDirty = GeneratedColumn<bool>(
    'is_dirty',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_dirty" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    gymId,
    name,
    category,
    durationValue,
    durationUnit,
    priceCentavos,
    isDayPass,
    isActive,
    sortOrder,
    updatedAt,
    isDirty,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'membership_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<MembershipPlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('gym_id')) {
      context.handle(
        _gymIdMeta,
        gymId.isAcceptableOrUnknown(data['gym_id']!, _gymIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gymIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('duration_value')) {
      context.handle(
        _durationValueMeta,
        durationValue.isAcceptableOrUnknown(
          data['duration_value']!,
          _durationValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationValueMeta);
    }
    if (data.containsKey('duration_unit')) {
      context.handle(
        _durationUnitMeta,
        durationUnit.isAcceptableOrUnknown(
          data['duration_unit']!,
          _durationUnitMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_durationUnitMeta);
    }
    if (data.containsKey('price_centavos')) {
      context.handle(
        _priceCentavosMeta,
        priceCentavos.isAcceptableOrUnknown(
          data['price_centavos']!,
          _priceCentavosMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_priceCentavosMeta);
    }
    if (data.containsKey('is_day_pass')) {
      context.handle(
        _isDayPassMeta,
        isDayPass.isAcceptableOrUnknown(data['is_day_pass']!, _isDayPassMeta),
      );
    } else if (isInserting) {
      context.missing(_isDayPassMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    } else if (isInserting) {
      context.missing(_isActiveMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('is_dirty')) {
      context.handle(
        _isDirtyMeta,
        isDirty.isAcceptableOrUnknown(data['is_dirty']!, _isDirtyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {gymId, name, category},
  ];
  @override
  MembershipPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MembershipPlan(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      gymId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gym_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      durationValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_value'],
      )!,
      durationUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}duration_unit'],
      )!,
      priceCentavos: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}price_centavos'],
      )!,
      isDayPass: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_day_pass'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isDirty: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_dirty'],
      )!,
    );
  }

  @override
  $MembershipPlansTable createAlias(String alias) {
    return $MembershipPlansTable(attachedDatabase, alias);
  }
}

class MembershipPlan extends DataClass implements Insertable<MembershipPlan> {
  final String id;
  final String gymId;
  final String name;
  final String category;
  final int durationValue;
  final String durationUnit;
  final int priceCentavos;
  final bool isDayPass;
  final bool isActive;
  final int sortOrder;
  final DateTime updatedAt;
  final bool isDirty;
  const MembershipPlan({
    required this.id,
    required this.gymId,
    required this.name,
    required this.category,
    required this.durationValue,
    required this.durationUnit,
    required this.priceCentavos,
    required this.isDayPass,
    required this.isActive,
    required this.sortOrder,
    required this.updatedAt,
    required this.isDirty,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['gym_id'] = Variable<String>(gymId);
    map['name'] = Variable<String>(name);
    map['category'] = Variable<String>(category);
    map['duration_value'] = Variable<int>(durationValue);
    map['duration_unit'] = Variable<String>(durationUnit);
    map['price_centavos'] = Variable<int>(priceCentavos);
    map['is_day_pass'] = Variable<bool>(isDayPass);
    map['is_active'] = Variable<bool>(isActive);
    map['sort_order'] = Variable<int>(sortOrder);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_dirty'] = Variable<bool>(isDirty);
    return map;
  }

  MembershipPlansCompanion toCompanion(bool nullToAbsent) {
    return MembershipPlansCompanion(
      id: Value(id),
      gymId: Value(gymId),
      name: Value(name),
      category: Value(category),
      durationValue: Value(durationValue),
      durationUnit: Value(durationUnit),
      priceCentavos: Value(priceCentavos),
      isDayPass: Value(isDayPass),
      isActive: Value(isActive),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
      isDirty: Value(isDirty),
    );
  }

  factory MembershipPlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MembershipPlan(
      id: serializer.fromJson<String>(json['id']),
      gymId: serializer.fromJson<String>(json['gymId']),
      name: serializer.fromJson<String>(json['name']),
      category: serializer.fromJson<String>(json['category']),
      durationValue: serializer.fromJson<int>(json['durationValue']),
      durationUnit: serializer.fromJson<String>(json['durationUnit']),
      priceCentavos: serializer.fromJson<int>(json['priceCentavos']),
      isDayPass: serializer.fromJson<bool>(json['isDayPass']),
      isActive: serializer.fromJson<bool>(json['isActive']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isDirty: serializer.fromJson<bool>(json['isDirty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'gymId': serializer.toJson<String>(gymId),
      'name': serializer.toJson<String>(name),
      'category': serializer.toJson<String>(category),
      'durationValue': serializer.toJson<int>(durationValue),
      'durationUnit': serializer.toJson<String>(durationUnit),
      'priceCentavos': serializer.toJson<int>(priceCentavos),
      'isDayPass': serializer.toJson<bool>(isDayPass),
      'isActive': serializer.toJson<bool>(isActive),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isDirty': serializer.toJson<bool>(isDirty),
    };
  }

  MembershipPlan copyWith({
    String? id,
    String? gymId,
    String? name,
    String? category,
    int? durationValue,
    String? durationUnit,
    int? priceCentavos,
    bool? isDayPass,
    bool? isActive,
    int? sortOrder,
    DateTime? updatedAt,
    bool? isDirty,
  }) => MembershipPlan(
    id: id ?? this.id,
    gymId: gymId ?? this.gymId,
    name: name ?? this.name,
    category: category ?? this.category,
    durationValue: durationValue ?? this.durationValue,
    durationUnit: durationUnit ?? this.durationUnit,
    priceCentavos: priceCentavos ?? this.priceCentavos,
    isDayPass: isDayPass ?? this.isDayPass,
    isActive: isActive ?? this.isActive,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedAt: updatedAt ?? this.updatedAt,
    isDirty: isDirty ?? this.isDirty,
  );
  MembershipPlan copyWithCompanion(MembershipPlansCompanion data) {
    return MembershipPlan(
      id: data.id.present ? data.id.value : this.id,
      gymId: data.gymId.present ? data.gymId.value : this.gymId,
      name: data.name.present ? data.name.value : this.name,
      category: data.category.present ? data.category.value : this.category,
      durationValue: data.durationValue.present
          ? data.durationValue.value
          : this.durationValue,
      durationUnit: data.durationUnit.present
          ? data.durationUnit.value
          : this.durationUnit,
      priceCentavos: data.priceCentavos.present
          ? data.priceCentavos.value
          : this.priceCentavos,
      isDayPass: data.isDayPass.present ? data.isDayPass.value : this.isDayPass,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isDirty: data.isDirty.present ? data.isDirty.value : this.isDirty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MembershipPlan(')
          ..write('id: $id, ')
          ..write('gymId: $gymId, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('durationValue: $durationValue, ')
          ..write('durationUnit: $durationUnit, ')
          ..write('priceCentavos: $priceCentavos, ')
          ..write('isDayPass: $isDayPass, ')
          ..write('isActive: $isActive, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDirty: $isDirty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    gymId,
    name,
    category,
    durationValue,
    durationUnit,
    priceCentavos,
    isDayPass,
    isActive,
    sortOrder,
    updatedAt,
    isDirty,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MembershipPlan &&
          other.id == this.id &&
          other.gymId == this.gymId &&
          other.name == this.name &&
          other.category == this.category &&
          other.durationValue == this.durationValue &&
          other.durationUnit == this.durationUnit &&
          other.priceCentavos == this.priceCentavos &&
          other.isDayPass == this.isDayPass &&
          other.isActive == this.isActive &&
          other.sortOrder == this.sortOrder &&
          other.updatedAt == this.updatedAt &&
          other.isDirty == this.isDirty);
}

class MembershipPlansCompanion extends UpdateCompanion<MembershipPlan> {
  final Value<String> id;
  final Value<String> gymId;
  final Value<String> name;
  final Value<String> category;
  final Value<int> durationValue;
  final Value<String> durationUnit;
  final Value<int> priceCentavos;
  final Value<bool> isDayPass;
  final Value<bool> isActive;
  final Value<int> sortOrder;
  final Value<DateTime> updatedAt;
  final Value<bool> isDirty;
  final Value<int> rowid;
  const MembershipPlansCompanion({
    this.id = const Value.absent(),
    this.gymId = const Value.absent(),
    this.name = const Value.absent(),
    this.category = const Value.absent(),
    this.durationValue = const Value.absent(),
    this.durationUnit = const Value.absent(),
    this.priceCentavos = const Value.absent(),
    this.isDayPass = const Value.absent(),
    this.isActive = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isDirty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MembershipPlansCompanion.insert({
    required String id,
    required String gymId,
    required String name,
    this.category = const Value.absent(),
    required int durationValue,
    required String durationUnit,
    required int priceCentavos,
    required bool isDayPass,
    required bool isActive,
    required int sortOrder,
    required DateTime updatedAt,
    this.isDirty = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       gymId = Value(gymId),
       name = Value(name),
       durationValue = Value(durationValue),
       durationUnit = Value(durationUnit),
       priceCentavos = Value(priceCentavos),
       isDayPass = Value(isDayPass),
       isActive = Value(isActive),
       sortOrder = Value(sortOrder),
       updatedAt = Value(updatedAt);
  static Insertable<MembershipPlan> custom({
    Expression<String>? id,
    Expression<String>? gymId,
    Expression<String>? name,
    Expression<String>? category,
    Expression<int>? durationValue,
    Expression<String>? durationUnit,
    Expression<int>? priceCentavos,
    Expression<bool>? isDayPass,
    Expression<bool>? isActive,
    Expression<int>? sortOrder,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isDirty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (gymId != null) 'gym_id': gymId,
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (durationValue != null) 'duration_value': durationValue,
      if (durationUnit != null) 'duration_unit': durationUnit,
      if (priceCentavos != null) 'price_centavos': priceCentavos,
      if (isDayPass != null) 'is_day_pass': isDayPass,
      if (isActive != null) 'is_active': isActive,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isDirty != null) 'is_dirty': isDirty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MembershipPlansCompanion copyWith({
    Value<String>? id,
    Value<String>? gymId,
    Value<String>? name,
    Value<String>? category,
    Value<int>? durationValue,
    Value<String>? durationUnit,
    Value<int>? priceCentavos,
    Value<bool>? isDayPass,
    Value<bool>? isActive,
    Value<int>? sortOrder,
    Value<DateTime>? updatedAt,
    Value<bool>? isDirty,
    Value<int>? rowid,
  }) {
    return MembershipPlansCompanion(
      id: id ?? this.id,
      gymId: gymId ?? this.gymId,
      name: name ?? this.name,
      category: category ?? this.category,
      durationValue: durationValue ?? this.durationValue,
      durationUnit: durationUnit ?? this.durationUnit,
      priceCentavos: priceCentavos ?? this.priceCentavos,
      isDayPass: isDayPass ?? this.isDayPass,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      isDirty: isDirty ?? this.isDirty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (gymId.present) {
      map['gym_id'] = Variable<String>(gymId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (durationValue.present) {
      map['duration_value'] = Variable<int>(durationValue.value);
    }
    if (durationUnit.present) {
      map['duration_unit'] = Variable<String>(durationUnit.value);
    }
    if (priceCentavos.present) {
      map['price_centavos'] = Variable<int>(priceCentavos.value);
    }
    if (isDayPass.present) {
      map['is_day_pass'] = Variable<bool>(isDayPass.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isDirty.present) {
      map['is_dirty'] = Variable<bool>(isDirty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembershipPlansCompanion(')
          ..write('id: $id, ')
          ..write('gymId: $gymId, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('durationValue: $durationValue, ')
          ..write('durationUnit: $durationUnit, ')
          ..write('priceCentavos: $priceCentavos, ')
          ..write('isDayPass: $isDayPass, ')
          ..write('isActive: $isActive, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isDirty: $isDirty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MembersTable members = $MembersTable(this);
  late final $MembershipPlansTable membershipPlans = $MembershipPlansTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    members,
    membershipPlans,
  ];
}

typedef $$MembersTableCreateCompanionBuilder =
    MembersCompanion Function({
      required String id,
      required String gymId,
      required String homeLocationId,
      Value<String> memberCode,
      required String firstName,
      Value<String> lastName,
      Value<String> phone,
      Value<String> email,
      Value<DateTime?> dateOfBirth,
      required String memberType,
      Value<String> notes,
      Value<DateTime?> currentEndDate,
      Value<String?> currentPlanCategory,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<DateTime?> archivedAt,
      Value<bool> isDirty,
      Value<int> rowid,
    });
typedef $$MembersTableUpdateCompanionBuilder =
    MembersCompanion Function({
      Value<String> id,
      Value<String> gymId,
      Value<String> homeLocationId,
      Value<String> memberCode,
      Value<String> firstName,
      Value<String> lastName,
      Value<String> phone,
      Value<String> email,
      Value<DateTime?> dateOfBirth,
      Value<String> memberType,
      Value<String> notes,
      Value<DateTime?> currentEndDate,
      Value<String?> currentPlanCategory,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<DateTime?> archivedAt,
      Value<bool> isDirty,
      Value<int> rowid,
    });

class $$MembersTableFilterComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gymId => $composableBuilder(
    column: $table.gymId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get homeLocationId => $composableBuilder(
    column: $table.homeLocationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memberCode => $composableBuilder(
    column: $table.memberCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memberType => $composableBuilder(
    column: $table.memberType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get currentEndDate => $composableBuilder(
    column: $table.currentEndDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentPlanCategory => $composableBuilder(
    column: $table.currentPlanCategory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MembersTableOrderingComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gymId => $composableBuilder(
    column: $table.gymId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get homeLocationId => $composableBuilder(
    column: $table.homeLocationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memberCode => $composableBuilder(
    column: $table.memberCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firstName => $composableBuilder(
    column: $table.firstName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastName => $composableBuilder(
    column: $table.lastName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memberType => $composableBuilder(
    column: $table.memberType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get currentEndDate => $composableBuilder(
    column: $table.currentEndDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentPlanCategory => $composableBuilder(
    column: $table.currentPlanCategory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get gymId =>
      $composableBuilder(column: $table.gymId, builder: (column) => column);

  GeneratedColumn<String> get homeLocationId => $composableBuilder(
    column: $table.homeLocationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get memberCode => $composableBuilder(
    column: $table.memberCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firstName =>
      $composableBuilder(column: $table.firstName, builder: (column) => column);

  GeneratedColumn<String> get lastName =>
      $composableBuilder(column: $table.lastName, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<DateTime> get dateOfBirth => $composableBuilder(
    column: $table.dateOfBirth,
    builder: (column) => column,
  );

  GeneratedColumn<String> get memberType => $composableBuilder(
    column: $table.memberType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get currentEndDate => $composableBuilder(
    column: $table.currentEndDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentPlanCategory => $composableBuilder(
    column: $table.currentPlanCategory,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDirty =>
      $composableBuilder(column: $table.isDirty, builder: (column) => column);
}

class $$MembersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MembersTable,
          Member,
          $$MembersTableFilterComposer,
          $$MembersTableOrderingComposer,
          $$MembersTableAnnotationComposer,
          $$MembersTableCreateCompanionBuilder,
          $$MembersTableUpdateCompanionBuilder,
          (Member, BaseReferences<_$AppDatabase, $MembersTable, Member>),
          Member,
          PrefetchHooks Function()
        > {
  $$MembersTableTableManager(_$AppDatabase db, $MembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> gymId = const Value.absent(),
                Value<String> homeLocationId = const Value.absent(),
                Value<String> memberCode = const Value.absent(),
                Value<String> firstName = const Value.absent(),
                Value<String> lastName = const Value.absent(),
                Value<String> phone = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<DateTime?> dateOfBirth = const Value.absent(),
                Value<String> memberType = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<DateTime?> currentEndDate = const Value.absent(),
                Value<String?> currentPlanCategory = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MembersCompanion(
                id: id,
                gymId: gymId,
                homeLocationId: homeLocationId,
                memberCode: memberCode,
                firstName: firstName,
                lastName: lastName,
                phone: phone,
                email: email,
                dateOfBirth: dateOfBirth,
                memberType: memberType,
                notes: notes,
                currentEndDate: currentEndDate,
                currentPlanCategory: currentPlanCategory,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                isDirty: isDirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String gymId,
                required String homeLocationId,
                Value<String> memberCode = const Value.absent(),
                required String firstName,
                Value<String> lastName = const Value.absent(),
                Value<String> phone = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<DateTime?> dateOfBirth = const Value.absent(),
                required String memberType,
                Value<String> notes = const Value.absent(),
                Value<DateTime?> currentEndDate = const Value.absent(),
                Value<String?> currentPlanCategory = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MembersCompanion.insert(
                id: id,
                gymId: gymId,
                homeLocationId: homeLocationId,
                memberCode: memberCode,
                firstName: firstName,
                lastName: lastName,
                phone: phone,
                email: email,
                dateOfBirth: dateOfBirth,
                memberType: memberType,
                notes: notes,
                currentEndDate: currentEndDate,
                currentPlanCategory: currentPlanCategory,
                createdAt: createdAt,
                updatedAt: updatedAt,
                archivedAt: archivedAt,
                isDirty: isDirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MembersTable,
      Member,
      $$MembersTableFilterComposer,
      $$MembersTableOrderingComposer,
      $$MembersTableAnnotationComposer,
      $$MembersTableCreateCompanionBuilder,
      $$MembersTableUpdateCompanionBuilder,
      (Member, BaseReferences<_$AppDatabase, $MembersTable, Member>),
      Member,
      PrefetchHooks Function()
    >;
typedef $$MembershipPlansTableCreateCompanionBuilder =
    MembershipPlansCompanion Function({
      required String id,
      required String gymId,
      required String name,
      Value<String> category,
      required int durationValue,
      required String durationUnit,
      required int priceCentavos,
      required bool isDayPass,
      required bool isActive,
      required int sortOrder,
      required DateTime updatedAt,
      Value<bool> isDirty,
      Value<int> rowid,
    });
typedef $$MembershipPlansTableUpdateCompanionBuilder =
    MembershipPlansCompanion Function({
      Value<String> id,
      Value<String> gymId,
      Value<String> name,
      Value<String> category,
      Value<int> durationValue,
      Value<String> durationUnit,
      Value<int> priceCentavos,
      Value<bool> isDayPass,
      Value<bool> isActive,
      Value<int> sortOrder,
      Value<DateTime> updatedAt,
      Value<bool> isDirty,
      Value<int> rowid,
    });

class $$MembershipPlansTableFilterComposer
    extends Composer<_$AppDatabase, $MembershipPlansTable> {
  $$MembershipPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gymId => $composableBuilder(
    column: $table.gymId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationValue => $composableBuilder(
    column: $table.durationValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get durationUnit => $composableBuilder(
    column: $table.durationUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get priceCentavos => $composableBuilder(
    column: $table.priceCentavos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDayPass => $composableBuilder(
    column: $table.isDayPass,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MembershipPlansTableOrderingComposer
    extends Composer<_$AppDatabase, $MembershipPlansTable> {
  $$MembershipPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gymId => $composableBuilder(
    column: $table.gymId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationValue => $composableBuilder(
    column: $table.durationValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get durationUnit => $composableBuilder(
    column: $table.durationUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get priceCentavos => $composableBuilder(
    column: $table.priceCentavos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDayPass => $composableBuilder(
    column: $table.isDayPass,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDirty => $composableBuilder(
    column: $table.isDirty,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MembershipPlansTableAnnotationComposer
    extends Composer<_$AppDatabase, $MembershipPlansTable> {
  $$MembershipPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get gymId =>
      $composableBuilder(column: $table.gymId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get durationValue => $composableBuilder(
    column: $table.durationValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get durationUnit => $composableBuilder(
    column: $table.durationUnit,
    builder: (column) => column,
  );

  GeneratedColumn<int> get priceCentavos => $composableBuilder(
    column: $table.priceCentavos,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDayPass =>
      $composableBuilder(column: $table.isDayPass, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isDirty =>
      $composableBuilder(column: $table.isDirty, builder: (column) => column);
}

class $$MembershipPlansTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MembershipPlansTable,
          MembershipPlan,
          $$MembershipPlansTableFilterComposer,
          $$MembershipPlansTableOrderingComposer,
          $$MembershipPlansTableAnnotationComposer,
          $$MembershipPlansTableCreateCompanionBuilder,
          $$MembershipPlansTableUpdateCompanionBuilder,
          (
            MembershipPlan,
            BaseReferences<
              _$AppDatabase,
              $MembershipPlansTable,
              MembershipPlan
            >,
          ),
          MembershipPlan,
          PrefetchHooks Function()
        > {
  $$MembershipPlansTableTableManager(
    _$AppDatabase db,
    $MembershipPlansTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembershipPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembershipPlansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembershipPlansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> gymId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<int> durationValue = const Value.absent(),
                Value<String> durationUnit = const Value.absent(),
                Value<int> priceCentavos = const Value.absent(),
                Value<bool> isDayPass = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isDirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MembershipPlansCompanion(
                id: id,
                gymId: gymId,
                name: name,
                category: category,
                durationValue: durationValue,
                durationUnit: durationUnit,
                priceCentavos: priceCentavos,
                isDayPass: isDayPass,
                isActive: isActive,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                isDirty: isDirty,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String gymId,
                required String name,
                Value<String> category = const Value.absent(),
                required int durationValue,
                required String durationUnit,
                required int priceCentavos,
                required bool isDayPass,
                required bool isActive,
                required int sortOrder,
                required DateTime updatedAt,
                Value<bool> isDirty = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MembershipPlansCompanion.insert(
                id: id,
                gymId: gymId,
                name: name,
                category: category,
                durationValue: durationValue,
                durationUnit: durationUnit,
                priceCentavos: priceCentavos,
                isDayPass: isDayPass,
                isActive: isActive,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                isDirty: isDirty,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MembershipPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MembershipPlansTable,
      MembershipPlan,
      $$MembershipPlansTableFilterComposer,
      $$MembershipPlansTableOrderingComposer,
      $$MembershipPlansTableAnnotationComposer,
      $$MembershipPlansTableCreateCompanionBuilder,
      $$MembershipPlansTableUpdateCompanionBuilder,
      (
        MembershipPlan,
        BaseReferences<_$AppDatabase, $MembershipPlansTable, MembershipPlan>,
      ),
      MembershipPlan,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db, _db.members);
  $$MembershipPlansTableTableManager get membershipPlans =>
      $$MembershipPlansTableTableManager(_db, _db.membershipPlans);
}
